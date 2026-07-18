#!/usr/bin/env python3
"""Decode synchronized Build 91 Linux udelay a3/a4/a5 captures."""

import argparse
import glob
import os
import sys

import p3_decode_build80_ila_csv as build80
import p3_decode_build84_ila_csv as build84


BRANCH_PC = 0xFFFFFFFF807D8AA4
BRANCH_PC_LOW24 = BRANCH_PC & 0xFFFFFF
SUB_PC_LOW24 = 0x7D8AA2
MASK40 = (1 << 40) - 1


def find_capture_set(directory):
    matches = sorted(
        glob.glob(
            os.path.join(
                directory,
                "ila_capture_build91_*_u_bd_openpiton_top_i_axis_ila_1.csv",
            )
        ),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 91 axis_ila_1 CSV in {directory}")
    axis1 = matches[-1]
    result = {
        "ila1": axis1,
        "ila2": axis1.replace("_axis_ila_1.csv", "_axis_ila_2.csv"),
        "ila3": axis1.replace("_axis_ila_1.csv", "_axis_ila_3.csv"),
        "control": axis1.replace(
            "_u_bd_openpiton_top_i_axis_ila_1.csv", "_u_ila_build90.csv"
        ),
    }
    for label, path in result.items():
        if not os.path.isfile(path):
            raise FileNotFoundError(f"matching Build 91 {label} CSV is missing: {path}")
    return result


def find_ltx(directory, explicit=None):
    if explicit:
        if not os.path.isfile(explicit):
            raise FileNotFoundError(f"Build 91 LTX does not exist: {explicit}")
        return explicit
    path = os.path.abspath(
        os.path.join(directory, "..", "p3_top_build91_udelay_values.ltx")
    )
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Build 91 LTX does not exist: {path}")
    return path


def control_pc(columns):
    matches = [
        series
        for name, series in columns.items()
        if "commit_instr_id_commit[0][pc]" in name and "[63:0]" in name
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one Build 91 full-PC column, found {len(matches)}")
    return matches[0]


def classify(start, target, raw_time, delta):
    expected_delta = (raw_time - start) & MASK40
    if delta != expected_delta:
        return "SUB_OR_GPR_RESULT_MISMATCH"
    if target == 0:
        return "ZERO_THRESHOLD_SHOULD_EXIT"
    if delta >= target:
        return "BRANCH_SHOULD_EXIT"
    if delta == 0:
        return "TIME_NOT_ADVANCING_AT_CAPTURE"
    if target >= (1 << 32) and target > delta * 1024:
        return "THRESHOLD_IMPLAUSIBLY_LARGE"
    return "UDELAY_STILL_WAITING"


def last_sample_with_pc(payload, pc_low24, before):
    matches = [
        index
        for index in range(max(0, before - 128), before + 1)
        if (payload[index] & 0xFFFFFF) == pc_low24
    ]
    if not matches:
        raise ValueError(f"no PC 0x{pc_low24:06x} before trigger")
    return matches[-1]


def validate_sync(control_pc_series, payloads, triggers):
    if len(set(triggers)) != 1:
        raise ValueError(f"Build 91 trigger indices differ: {triggers}")
    trigger = triggers[0]
    if control_pc_series[trigger] != BRANCH_PC:
        raise ValueError(
            f"control trigger PC is 0x{control_pc_series[trigger]:016x}, "
            f"expected 0x{BRANCH_PC:016x}"
        )
    for index, payload in enumerate(payloads, start=1):
        if (payload[trigger] & 0xFFFFFF) != BRANCH_PC_LOW24:
            raise ValueError(
                f"axis_ila_{index} trigger PC is "
                f"0x{payload[trigger] & 0xFFFFFF:06x}"
            )
    first = max(0, trigger - 16)
    last = min(min(len(series) for series in payloads), trigger + 17)
    for sample in range(first, last):
        pcs = [series[sample] & 0xFFFFFF for series in payloads]
        if len(set(pcs)) != 1:
            raise ValueError(
                f"Build 91 register ILAs are not synchronized at sample {sample}: {pcs}"
            )
    return trigger


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 91 CSV files")
    parser.add_argument("--ltx", help="matching Build 91 LTX")
    args = parser.parse_args()

    try:
        paths = find_capture_set(args.capture)
        ltx = find_ltx(args.capture, args.ltx)
        layouts = build80.load_ltx_layout(ltx)
        maps = build84.vector_maps(layouts)
        captures = {
            label: build80.csvutil.read_capture(path)
            for label, path in paths.items()
        }
        control = control_pc(captures["control"][0])
        payloads = [
            build80.reconstruct_from_net_map(
                captures[f"ila{index}"][0], maps[f"ila{index}"], 64
            )
            for index in range(1, 4)
        ]
        trigger = validate_sync(
            control,
            payloads,
            [
                captures["control"][2],
                captures["ila1"][2],
                captures["ila2"][2],
                captures["ila3"][2],
            ],
        )
        raw_sample = last_sample_with_pc(payloads[2], SUB_PC_LOW24, trigger)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    start = payloads[0][trigger] >> 24
    target = payloads[1][trigger] >> 24
    raw_time = payloads[2][raw_sample] >> 24
    delta = payloads[2][trigger] >> 24
    expected_delta = (raw_time - start) & MASK40
    verdict = classify(start, target, raw_time, delta)
    branch_samples = [
        (index, payloads[2][index] >> 24)
        for index in range(trigger, min(len(payloads[2]), trigger + 256))
        if (payloads[2][index] & 0xFFFFFF) == BRANCH_PC_LOW24
    ]

    print("Build 91 synchronized Linux udelay capture:")
    for label in ("control", "ila1", "ila2", "ila3"):
        print(f"  {label}: {paths[label]}")
    print(f"  trigger sample={trigger} pc=0x{control[trigger]:016x}")
    print(f"  raw-time sample={raw_sample} pc_low24=0x{SUB_PC_LOW24:06x}")
    print(f"  a3/start_low40    =0x{start:010x} ({start})")
    print(f"  a4/threshold_low40=0x{target:010x} ({target})")
    print(f"  a5/raw_time_low40 =0x{raw_time:010x} ({raw_time})")
    print(f"  a5/delta_low40    =0x{delta:010x} ({delta})")
    print(f"  expected_delta    =0x{expected_delta:010x} ({expected_delta})")
    print(f"  delta_matches_sub={delta == expected_delta}")
    print(f"  delta_ge_threshold={delta >= target}")
    print(
        "  branch_delta_samples="
        + " ".join(f"{index - trigger:+d}:0x{value:010x}" for index, value in branch_samples[:16])
    )
    print(f"VERDICT: {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
