#!/usr/bin/env python3
"""Decode synchronized Build 92 udelay caller-context captures."""

import argparse
import glob
import os
import sys

import p3_decode_build80_ila_csv as build80
import p3_decode_build84_ila_csv as build84


BRANCH_PC = 0xFFFFFFFF807D8AA4
BRANCH_PC_LOW24 = BRANCH_PC & 0xFFFFFF
MASK40 = (1 << 40) - 1


def sign_extend40(value):
    value &= MASK40
    if value & (1 << 39):
        return value | (~MASK40 & ((1 << 64) - 1))
    return value


def find_capture_set(directory):
    matches = sorted(
        glob.glob(
            os.path.join(
                directory,
                "ila_capture_build92_*_u_bd_openpiton_top_i_axis_ila_1.csv",
            )
        ),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 92 axis_ila_1 CSV in {directory}")
    axis1 = matches[-1]
    paths = {
        "ra": axis1,
        "a0": axis1.replace("_axis_ila_1.csv", "_axis_ila_2.csv"),
        "sp": axis1.replace("_axis_ila_1.csv", "_axis_ila_3.csv"),
        "control": axis1.replace(
            "_u_bd_openpiton_top_i_axis_ila_1.csv", "_u_ila_build90.csv"
        ),
    }
    for label, path in paths.items():
        if not os.path.isfile(path):
            raise FileNotFoundError(f"matching Build 92 {label} CSV is missing: {path}")
    return paths


def control_pc(columns):
    matches = [
        series
        for name, series in columns.items()
        if "commit_instr_id_commit[0][pc]" in name and "[63:0]" in name
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one Build 92 full-PC column, found {len(matches)}")
    return matches[0]


def validate_sync(control, payloads, triggers):
    if len(set(triggers)) != 1:
        raise ValueError(f"Build 92 trigger indices differ: {triggers}")
    trigger = triggers[0]
    if control[trigger] != BRANCH_PC:
        raise ValueError(f"control trigger PC is 0x{control[trigger]:016x}")
    for index, payload in enumerate(payloads, start=1):
        if (payload[trigger] & 0xFFFFFF) != BRANCH_PC_LOW24:
            raise ValueError(
                f"axis_ila_{index} trigger PC is 0x{payload[trigger] & 0xFFFFFF:06x}"
            )
    first = max(0, trigger - 16)
    last = min(min(len(series) for series in payloads), trigger + 17)
    for sample in range(first, last):
        pcs = [series[sample] & 0xFFFFFF for series in payloads]
        if len(set(pcs)) != 1:
            raise ValueError(f"Build 92 ILAs differ at sample {sample}: {pcs}")
    return trigger


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 92 CSV files")
    parser.add_argument("--ltx", required=True, help="matching Build 92 LTX")
    args = parser.parse_args()

    try:
        paths = find_capture_set(args.capture)
        layouts = build80.load_ltx_layout(args.ltx)
        maps = build84.vector_maps(layouts)
        captures = {
            label: build80.csvutil.read_capture(path)
            for label, path in paths.items()
        }
        control = control_pc(captures["control"][0])
        payloads = [
            build80.reconstruct_from_net_map(
                captures[label][0], maps[f"ila{index}"], 64
            )
            for index, label in enumerate(("ra", "a0", "sp"), start=1)
        ]
        trigger = validate_sync(
            control,
            payloads,
            [
                captures["control"][2],
                captures["ra"][2],
                captures["a0"][2],
                captures["sp"][2],
            ],
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    ra = sign_extend40(payloads[0][trigger] >> 24)
    delay = payloads[1][trigger] >> 24
    sp = sign_extend40(payloads[2][trigger] >> 24)
    samples = []
    for index in range(trigger, min(len(payloads[0]), trigger + 256)):
        if (payloads[0][index] & 0xFFFFFF) != BRANCH_PC_LOW24:
            continue
        samples.append(
            (
                index - trigger,
                sign_extend40(payloads[0][index] >> 24),
                payloads[1][index] >> 24,
                sign_extend40(payloads[2][index] >> 24),
            )
        )

    print("Build 92 synchronized Linux udelay caller capture:")
    print(f"  trigger sample={trigger} pc=0x{control[trigger]:016x}")
    print(f"  ra=0x{ra:016x}")
    print(f"  candidate_call_pc_16=0x{(ra - 2) & ((1 << 64) - 1):016x}")
    print(f"  candidate_call_pc_32=0x{(ra - 4) & ((1 << 64) - 1):016x}")
    print(f"  a0/delay_us={delay}")
    print(f"  sp=0x{sp:016x}")
    print(
        "  repeated_branch_context="
        + " ".join(
            f"{offset:+d}:ra=0x{sample_ra:016x},a0={sample_a0},sp=0x{sample_sp:016x}"
            for offset, sample_ra, sample_a0, sample_sp in samples[:8]
        )
    )
    print("VERDICT: UDELAY_CALLER_CAPTURED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
