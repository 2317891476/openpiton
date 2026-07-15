#!/usr/bin/env python3
"""Decode the causal Build 75 single-hart PC/L1.5 ILA capture."""

import argparse
import csv
import glob
import os
import shutil
import subprocess
import sys


REQ_FLAGS = [
    "fetch_state_0",
    "fetch_state_1",
    "fetch_state_2",
    "acklogic_pcx_s1",
    "pcx_ack_s3",
    "pcx_ack_s2",
    "pcx_ack_s1",
    "stall_s3",
    "stall_s2",
    "stall_s1",
    "val_s3",
    "val_s2",
    "val_s1",
    "pcx_header_ack",
    "pcx_ack",
    "pcx_val",
]

STALL_BITS = [
    "noack_trigger",
    "noc1_data_unavailable",
    "noc1_command_unavailable",
    "pcx_noc1_buffer_stall",
    "mshr_allocation_stall",
    "index_conflict_stall",
    "tag_match_stall",
    "decoder_stall_on_bypassed_index",
    "index_bypass_match",
    "decoder_stall_on_matched_mshr",
    "tagcheck_matched",
    "decoder_stall_on_mshr_allocation",
    "decoder_no_free_mshr",
    "pipe_mshr_val_s3",
    "pipe_mshr_writereq_val_s1",
    "l15_noc1buffer_req_val",
    "noc3_req_ack",
    "cpx_req_ack",
]


def parse_hex(value):
    text = value.strip().replace("_", "")
    if text.lower().startswith("0x"):
        text = text[2:]
    return int(text, 16)


def read_capture(path):
    with open(path, newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 3:
        raise ValueError(f"CSV has no samples: {path}")
    header = rows[0]
    samples = rows[2:]
    trigger_samples = []
    for sample_index, row in enumerate(samples):
        if len(row) != len(header):
            raise ValueError(f"sample {sample_index} has {len(row)} columns, expected {len(header)}")
        if row[2].strip() == "1":
            trigger_samples.append(sample_index)
    if len(trigger_samples) != 1:
        raise ValueError(f"expected one trigger sample, found {trigger_samples}")
    columns = {}
    for index, name in enumerate(header[3:], start=3):
        columns[name] = [parse_hex(row[index]) for row in samples]
    return columns, len(samples), trigger_samples[0]


def one_column(columns, token):
    matches = [name for name in columns if token in name]
    if len(matches) != 1:
        raise ValueError(f"expected one probe containing {token!r}, found {matches}")
    return matches[0], columns[matches[0]]


def decode_sample(columns, sample_index):
    names = {}
    values = {}
    for key, token in {
        "trigger": "p3_build75_noack_trigger",
        "count": "p3_build75_noack_count",
        "req": "p3_build75_l15_req_bus",
        "stall": "p3_build75_l15_stall_bus",
        "pc": "[pc]",
        "valid": "[valid]",
        "fu": "[fu]",
        "op": "[op]",
        "commit_ack": "commit_ack[0]",
        "lsu_ready": "lsu_commit_ready_ex_commit",
        "lsu_commit": "lsu_commit_commit_ex",
    }.items():
        names[key], series = one_column(columns, token)
        values[key] = series[sample_index]

    req = values["req"]
    stall = values["stall"]
    decoded = {
        "names": names,
        "raw": values,
        "address": (req >> 24) & ((1 << 40) - 1),
        "rqtype": (req >> 19) & 0x1F,
        "size": (req >> 16) & 0x7,
        "req_flags": {name: (req >> bit) & 1 for bit, name in enumerate(REQ_FLAGS)},
        "tag": (stall >> 56) & 0xFF,
        "mshr_vals": (stall >> 48) & 0xFF,
        "noc1_avail": (stall >> 44) & 0xF,
        "noc1_data_avail": (stall >> 40) & 0xF,
        "noc1_reserve": (stall >> 36) & 0xF,
        "predecode_reqtype": (stall >> 30) & 0x3F,
        "predecode_size": (stall >> 27) & 0x7,
        "predecode_source": (stall >> 25) & 0x3,
        "noc1_needed": (stall >> 23) & 0x3,
        "req_8b": (stall >> 22) & 1,
        "req_16b": (stall >> 21) & 1,
        "noc1_req_sent": (stall >> 20) & 1,
        "noc1_data_sent": (stall >> 18) & 0x3,
        "stall_bits": {name: (stall >> bit) & 1 for bit, name in enumerate(STALL_BITS)},
    }
    return decoded


def classify(decoded):
    flags = decoded["req_flags"]
    stalls = decoded["stall_bits"]
    active = []
    if stalls["tag_match_stall"] or stalls["decoder_stall_on_matched_mshr"]:
        active.append("matched-MSHR/tag conflict")
    if stalls["index_conflict_stall"] or stalls["decoder_stall_on_bypassed_index"]:
        active.append("same-index S2/S3 conflict")
    if flags["stall_s2"] or flags["stall_s3"]:
        active.append("downstream S2/S3 backpressure")
    if (
        stalls["mshr_allocation_stall"]
        or stalls["decoder_stall_on_mshr_allocation"]
        or stalls["decoder_no_free_mshr"]
    ):
        active.append("no-free-MSHR allocation stall")
    if (
        stalls["pcx_noc1_buffer_stall"]
        or stalls["noc1_command_unavailable"]
        or stalls["noc1_data_unavailable"]
    ):
        active.append("NoC1 command/data credit stall")
    return active


def validation_failures(decoded, active):
    raw = decoded["raw"]
    flags = decoded["req_flags"]
    failures = []
    if decoded["tag"] != 0x75:
        failures.append("Build 75 diagnostic tag is missing")
    if raw["trigger"] != 1 or raw["count"] < 256:
        failures.append("capture did not reach the 256-cycle no-ack trigger")
    if flags["pcx_val"] != 1 or flags["pcx_ack"] != 0:
        failures.append("trigger sample is not a valid unacknowledged PCX request")
    if decoded["rqtype"] != 1:
        failures.append("trigger sample PCX request is not an ordinary store")
    if raw["valid"] != 1 or raw["fu"] != 2:
        failures.append("commit head is not a valid CVA6 STORE")
    if not active:
        failures.append("no concrete tag/index/S2-S3/MSHR/NoC1 blocker is active")
    return failures


def resolve_pc(pc, vmlinux):
    if not vmlinux or not os.path.isfile(vmlinux):
        return []
    prefix_candidates = [
        "riscv64-unknown-linux-gnu-",
        "riscv64-unknown-elf-",
    ]
    output = []
    for suffix, arguments in [
        ("addr2line", ["-e", vmlinux, "-f", "-C", "-i", hex(pc)]),
        (
            "objdump",
            [
                "-d",
                "--start-address",
                hex(pc),
                "--stop-address",
                hex(pc + 8),
                vmlinux,
            ],
        ),
    ]:
        tool = next(
            (shutil.which(prefix + suffix) for prefix in prefix_candidates if shutil.which(prefix + suffix)),
            None,
        )
        if not tool:
            output.append(f"{suffix}: tool not found")
            continue
        result = subprocess.run([tool, *arguments], check=False, text=True, capture_output=True)
        text = result.stdout.strip() or result.stderr.strip()
        output.append(f"{suffix}:\n{text}")
    return output


def find_capture(path):
    if os.path.isfile(path):
        return path
    matches = sorted(glob.glob(os.path.join(path, "ila_capture_build75_*_u_ila_build75.csv")))
    if len(matches) != 1:
        raise FileNotFoundError(f"expected one Build 75 causal CSV, found {len(matches)}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="Build 75 causal CSV or debug_build directory")
    parser.add_argument("--vmlinux", help="Linux vmlinux used to resolve the captured PC")
    args = parser.parse_args()

    try:
        path = find_capture(args.capture)
        columns, sample_count, trigger_sample = read_capture(path)
        decoded = decode_sample(columns, trigger_sample)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    raw = decoded["raw"]
    print(f"Build 75 capture: {path}")
    print(
        f"  samples={sample_count} trigger_sample={trigger_sample} "
        f"trigger={raw['trigger']} noack_count={raw['count']}"
    )
    print(
        "  L15 request: address=0x%010x rqtype=0x%x size=%d val=%d ack=%d header_ack=%d"
        % (
            decoded["address"],
            decoded["rqtype"],
            decoded["size"],
            decoded["req_flags"]["pcx_val"],
            decoded["req_flags"]["pcx_ack"],
            decoded["req_flags"]["pcx_header_ack"],
        )
    )
    print(
        "  commit: pc=0x%016x valid=%d fu=0x%x op=0x%x ack=%d lsu_ready=%d lsu_commit=%d"
        % (
            raw["pc"],
            raw["valid"],
            raw["fu"],
            raw["op"],
            raw["commit_ack"],
            raw["lsu_ready"],
            raw["lsu_commit"],
        )
    )
    print(
        "  L1.5 state: tag=0x%02x mshr_vals=0x%02x credits=%d data_credits=%d reserve=%d"
        % (
            decoded["tag"],
            decoded["mshr_vals"],
            decoded["noc1_avail"],
            decoded["noc1_data_avail"],
            decoded["noc1_reserve"],
        )
    )
    active = classify(decoded)
    print("  active blockers: " + (", ".join(active) if active else "none of the encoded causes"))
    for name, value in decoded["stall_bits"].items():
        print(f"    {name}={value}")

    for text in resolve_pc(raw["pc"], args.vmlinux):
        print(text)

    failures = validation_failures(decoded, active)
    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: Build 75 captured an unacknowledged store with a correlated commit PC")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
