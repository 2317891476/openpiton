#!/usr/bin/env python3
"""Decode Build 76/77 ECO commit-PC and packed-status ILA snapshots."""

import argparse
import csv
import glob
import os
import re
import shutil
import subprocess
import sys
from collections import Counter


FU_NAMES = {
    0x0: "NONE",
    0x1: "LOAD",
    0x2: "STORE",
    0x3: "ALU",
    0x4: "CTRL_FLOW",
    0x5: "MULT",
    0x6: "CSR",
    0x7: "FPU",
    0x8: "FPU_VEC",
    0x9: "CVXIF",
}

# Values from ariane_pkg.sv.  Keep this focused on the operations needed to
# distinguish a blocked store from the ordering instruction waiting behind it.
OP_NAMES = {
    0x1C: "FENCE",
    0x1D: "FENCE_I",
    0x1E: "SFENCE_VMA",
    0x23: "LD",
    0x24: "SD",
    0x25: "LW",
    0x26: "LWU",
    0x27: "SW",
    0x28: "LH",
    0x29: "LHU",
    0x2A: "SH",
    0x2B: "LB",
    0x2C: "SB",
    0x2D: "LBU",
}


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
            raise ValueError(
                f"sample {sample_index} has {len(row)} columns, expected {len(header)}"
            )
        if row[2].strip() == "1":
            trigger_samples.append(sample_index)
    if len(trigger_samples) != 1:
        raise ValueError(f"expected one trigger sample, found {trigger_samples}")
    columns = {
        name: [parse_hex(row[index]) for row in samples]
        for index, name in enumerate(header[3:], start=3)
    }
    return columns, len(samples), trigger_samples[0]


def reconstruct_split_probe(columns, core_token, width, aliases=None):
    pattern = re.compile(re.escape(core_token) + r"_(\d+)$")
    by_bit = {}
    for name, series in columns.items():
        match = pattern.search(name)
        if match:
            bit = int(match.group(1))
            if bit in by_bit:
                raise ValueError(f"duplicate {core_token} bit {bit}")
            by_bit[bit] = series
    for bit, token in (aliases or {}).items():
        matches = [series for name, series in columns.items() if token in name]
        if len(matches) > 1:
            raise ValueError(f"duplicate alias {token!r} for {core_token} bit {bit}")
        if matches:
            if bit in by_bit:
                raise ValueError(f"both regular and aliased {core_token} bit {bit}")
            by_bit[bit] = matches[0]
    missing = sorted(set(range(width)) - set(by_bit))
    extra = sorted(set(by_bit) - set(range(width)))
    if missing or extra:
        raise ValueError(
            f"{core_token} split probe mismatch: missing={missing} extra={extra}"
        )
    sample_count = len(by_bit[0])
    values = []
    for sample in range(sample_count):
        value = 0
        for bit in range(width):
            bit_value = by_bit[bit][sample]
            if bit_value not in (0, 1):
                raise ValueError(
                    f"{core_token} bit {bit} sample {sample} is not binary: {bit_value}"
                )
            value |= bit_value << bit
        values.append(value)
    return values


def decode_status(value):
    return {
        "valid": value & 1,
        "ack": (value >> 1) & 1,
        "fu": (value >> 2) & 0xF,
        "op": (value >> 6) & 0xFF,
        "lsu_addr_low": (value >> 14) & 0x7FF,
        "stall_s1": (value >> 25) & 1,
        "stall_s2": (value >> 26) & 1,
        "stall_s3": (value >> 27) & 1,
    }


def classify_status(status):
    """Return conclusions supported directly by CVA6 commit_stage.sv."""
    conclusions = []
    if status["valid"] == 1 and status["ack"] == 0:
        if status["fu"] == 0x6 and status["op"] == 0x1C:
            conclusions.append(
                "blocked FENCE: no_st_pending_i=0, so at least one earlier "
                "store has not drained"
            )
        elif status["fu"] == 0x2:
            conclusions.append(
                "blocked STORE: commit_lsu_ready_i=0, so the LSU cannot "
                "accept the retiring store"
            )
    if status["stall_s1"]:
        conclusions.append(
            "L1.5 S1 aggregate stall is asserted; the retained netlist does "
            "not identify the individual S1 blocker"
        )
    return conclusions


def find_capture_pair(path):
    if os.path.isdir(path):
        pc_matches = sorted(
            glob.glob(os.path.join(path, "ila_snapshot_build76_*_axis_ila_1.csv"))
        )
        if not pc_matches:
            raise FileNotFoundError(f"no Build 76 axis_ila_1 CSV in {path}")
        pc_path = pc_matches[-1]
        status_path = pc_path.replace("_axis_ila_1.csv", "_axis_ila_2.csv")
        if not os.path.isfile(status_path):
            raise FileNotFoundError(f"matching axis_ila_2 CSV is missing: {status_path}")
        return pc_path, status_path
    raise FileNotFoundError("capture argument must be a Build 76 capture directory")


def resolve_pc(pc, vmlinux):
    if not vmlinux or not os.path.isfile(vmlinux):
        return []
    prefixes = ["riscv64-unknown-linux-gnu-", "riscv64-unknown-elf-"]
    output = []
    for suffix, arguments in [
        ("addr2line", ["-e", vmlinux, "-f", "-C", "-i", hex(pc)]),
        (
            "objdump",
            [
                "-d",
                "--start-address",
                hex(max(0, pc - 8)),
                "--stop-address",
                hex(pc + 12),
                vmlinux,
            ],
        ),
    ]:
        tool = next(
            (
                shutil.which(prefix + suffix)
                for prefix in prefixes
                if shutil.which(prefix + suffix)
            ),
            None,
        )
        if not tool:
            output.append(f"{suffix}: tool not found")
            continue
        result = subprocess.run(
            [tool, *arguments], check=False, text=True, capture_output=True
        )
        text = result.stdout.strip() or result.stderr.strip()
        output.append(f"{suffix}:\n{text}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 76 snapshot CSVs")
    parser.add_argument("--vmlinux", help="Linux vmlinux used to resolve the captured PC")
    parser.add_argument(
        "--firmware-elf", help="OpenSBI fw_jump.elf used to resolve a firmware PC"
    )
    args = parser.parse_args()

    try:
        pc_path, status_path = find_capture_pair(args.capture)
        pc_columns, pc_count, pc_trigger = read_capture(pc_path)
        status_columns, status_count, status_trigger = read_capture(status_path)
        pc_series = reconstruct_split_probe(
            pc_columns, "axis_ila_1_probe0", 64
        )
        status_series = reconstruct_split_probe(
            status_columns,
            "axis_ila_2_probe0",
            28,
            aliases={0: "p3_build77_commit_valid"},
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    pc = pc_series[pc_trigger]
    status_raw = status_series[status_trigger]
    status = decode_status(status_raw)
    common_pc, common_count = Counter(pc_series).most_common(1)[0]
    stable_fraction = common_count / len(pc_series)
    common_status_raw, common_status_count = Counter(status_series).most_common(1)[0]
    status_stable_fraction = common_status_count / len(status_series)
    capture_name = (
        "Build 77"
        if any("p3_build77_commit_valid" in name for name in status_columns)
        else "Build 76"
    )

    print(f"{capture_name} PC capture: {pc_path}")
    print(f"{capture_name} status capture: {status_path}")
    print(
        f"  PC samples={pc_count} trigger={pc_trigger} "
        f"pc=0x{pc:016x} most_common=0x{common_pc:016x} "
        f"stable={common_count}/{pc_count} ({stable_fraction:.1%})"
    )
    print(
        "  commit: valid=%d ack=%d fu=0x%x(%s) op=0x%02x(%s) "
        "lsu_addr_low=0x%03x"
        % (
            status["valid"],
            status["ack"],
            status["fu"],
            FU_NAMES.get(status["fu"], "UNKNOWN"),
            status["op"],
            OP_NAMES.get(status["op"], "UNKNOWN"),
            status["lsu_addr_low"],
        )
    )
    print(
        "  L1.5 aggregate stalls: s1=%d s2=%d s3=%d"
        % (status["stall_s1"], status["stall_s2"], status["stall_s3"])
    )
    print(
        f"  status samples={status_count} trigger={status_trigger} "
        f"raw_low28=0x{status_raw:07x} most_common=0x{common_status_raw:07x} "
        f"stable={common_status_count}/{status_count} "
        f"({status_stable_fraction:.1%})"
    )
    for conclusion in classify_status(status):
        print(f"  conclusion: {conclusion}")

    if 0x80000000 <= pc < 0x80200000 and args.firmware_elf:
        for text in resolve_pc(pc, args.firmware_elf):
            print(text)
    else:
        linux_pc = pc
        if 0x80200000 <= pc < 0x90000000:
            linux_pc = 0xFFFFFFFF80000000 + (pc - 0x80200000)
            print(f"  Linux linked-address candidate: 0x{linux_pc:016x}")
        for text in resolve_pc(linux_pc, args.vmlinux):
            print(text)

    failures = []
    if pc == 0:
        failures.append("captured commit PC is zero")
    if stable_fraction < 0.90:
        failures.append("commit PC is not persistent across at least 90% of the snapshot")
    if status_stable_fraction < 0.90 or status_raw != common_status_raw:
        failures.append(
            "packed commit state is not persistent across at least 90% of the snapshot"
        )
    if status["valid"] != 1 or status["ack"] != 0:
        failures.append("packed state is not a valid unacknowledged commit head")
    if failures:
        print("INCONCLUSIVE:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: persistent unacknowledged commit PC captured from Build 66 logic")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
