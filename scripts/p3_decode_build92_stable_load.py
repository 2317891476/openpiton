#!/usr/bin/env python3
"""Decode Build 92 ra/a0/sp at a stable Linux load PC."""

import argparse
import glob
import os
import sys

import p3_decode_build80_ila_csv as build80
import p3_decode_build84_ila_csv as build84
import p3_decode_build92_udelay_caller as caller


def require_series(columns, token):
    matches = [series for name, series in columns.items() if token in name]
    if len(matches) != 1:
        raise ValueError(f"expected one column containing {token!r}, found {len(matches)}")
    return matches[0]


def find_paths(directory):
    matches = sorted(
        glob.glob(os.path.join(directory, "ila_snapshot_build92_*_u_ila_build90.csv")),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 92 stable-load snapshot in {directory}")
    control = matches[-1]
    prefix = control.replace("_u_ila_build90.csv", "")
    paths = {
        "control": control,
        "ra": prefix + "_u_bd_openpiton_top_i_axis_ila_1.csv",
        "a0": prefix + "_u_bd_openpiton_top_i_axis_ila_2.csv",
        "sp": prefix + "_u_bd_openpiton_top_i_axis_ila_3.csv",
    }
    for label, path in paths.items():
        if not os.path.isfile(path):
            raise FileNotFoundError(f"matching Build 92 {label} CSV is missing: {path}")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture")
    parser.add_argument("--ltx", required=True)
    args = parser.parse_args()
    try:
        paths = find_paths(args.capture)
        layouts = build80.load_ltx_layout(args.ltx)
        maps = build84.vector_maps(layouts)
        captures = {
            label: build80.csvutil.read_capture(path)
            for label, path in paths.items()
        }
        control_columns = captures["control"][0]
        pc = caller.control_pc(control_columns)
        payloads = [
            build80.reconstruct_from_net_map(
                captures[label][0], maps[f"ila{index}"], 64
            )
            for index, label in enumerate(("ra", "a0", "sp"), start=1)
        ]
        triggers = [captures[label][2] for label in ("control", "ra", "a0", "sp")]
        if len(set(triggers)) != 1:
            raise ValueError(f"Build 92 snapshot trigger indices differ: {triggers}")
        trigger = triggers[0]
        for index, payload in enumerate(payloads, start=1):
            if (payload[trigger] & 0xFFFFFF) != (pc[trigger] & 0xFFFFFF):
                raise ValueError(f"axis_ila_{index} PC does not match control")
        valid = require_series(control_columns, "[valid]")[trigger]
        ack = require_series(control_columns, "commit_ack")[trigger]
        fu = require_series(control_columns, "[fu][3:0]")[trigger]
        op = require_series(control_columns, "[op][7:0]")[trigger]
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    ra = caller.sign_extend40(payloads[0][trigger] >> 24)
    address = caller.sign_extend40(payloads[1][trigger] >> 24)
    sp = caller.sign_extend40(payloads[2][trigger] >> 24)
    print("Build 92 stable Linux load context:")
    print(f"  sample={trigger} pc=0x{pc[trigger]:016x}")
    print(f"  commit_valid_ack={valid}/{ack} fu=0x{fu:x} op=0x{op:x}")
    print(f"  ra=0x{ra:016x}")
    print(f"  candidate_call_pc_16=0x{(ra - 2) & ((1 << 64) - 1):016x}")
    print(f"  candidate_call_pc_32=0x{(ra - 4) & ((1 << 64) - 1):016x}")
    print(f"  a0/load_address=0x{address:016x}")
    print(f"  sp=0x{sp:016x}")
    print("VERDICT: STABLE_LOAD_CONTEXT_CAPTURED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
