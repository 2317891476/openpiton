#!/usr/bin/env python3
"""Decode Build 69 8x8 OpenSBI diagnostic ILA CSV captures."""

import argparse
import sys

import p3_decode_build65_ila_csv as b65
import p3_decode_build57_ila_csv as b57


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 69 debug_build directory")
    args = parser.parse_args()

    try:
        axis0 = b57.find_one(args.debug_build_dir, "ila_capture_build69_*axis_ila_0.csv")
        axis1 = b57.find_one(args.debug_build_dir, "ila_capture_build69_*axis_ila_1.csv")
        axis2 = b57.find_one(args.debug_build_dir, "ila_capture_build69_*axis_ila_2.csv")
        axis3 = b57.find_one(args.debug_build_dir, "ila_capture_build69_*axis_ila_3.csv")
        status = b65.decode_axis0_block(axis0)
        core = b57.decode_core_bus(axis1)
        block = b65.decode_block_bus(axis2)
        ddr = b57.decode_ddr_bus(axis3)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    failures = []
    warnings = []

    if status["core_seen"] is None:
        warnings.append("core_seen16 probe missing")
    elif not (status["core_seen"] & 0x1):
        failures.append("core reset did not release")

    seen = status["block_seen"]
    if seen is None:
        warnings.append("SPI-SD block seen16 probe missing")
    else:
        if not ((seen >> 1) & 1):
            warnings.append("no AXI SD read observed")
        if not ((seen >> 12) & 1):
            warnings.append("no SD block response observed")
        if (seen >> 8) & 1:
            failures.append("transaction manager reported an SD read error")

    if block["tm_succ"] == 0:
        warnings.append("transaction-manager success flag is low in the captured sample")
    if ddr["last_bresp"] != 0:
        failures.append("last DDR B response is not OKAY")
    if ddr["last_rresp"] != 0:
        failures.append("last DDR R response is not OKAY")
    if not (core["flags"] & 0x04):
        failures.append("core_bus rst_n_f flag is low")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        if warnings:
            print("WARN:")
            for warning in warnings:
                print(f"  - {warning}")
        return 1

    if warnings:
        print("WARN:")
        for warning in warnings:
            print(f"  - {warning}")

    print("PASS: Build 69 ILA decode found no hard reset/DDR failures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
