#!/usr/bin/env python3
"""Decode Build 46 no-stack DDR-probe ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


DDR_SEEN_BITS = [
    "reset_released",
    "awvalid_seen",
    "aw_fire_seen",
    "wvalid_seen",
    "w_fire_seen",
    "bvalid_seen",
    "b_fire_seen",
    "bresp_error_seen",
    "arvalid_seen",
    "ar_fire_seen",
    "rvalid_seen",
    "r_fire_seen",
    "rresp_error_seen",
    "write_addr_0x84_seen",
    "read_addr_0x84_seen",
    "awready_seen",
]


def read_last_values(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 3:
        raise ValueError(f"CSV has no samples: {path}")
    header = rows[0]
    samples = rows[2:]
    last = samples[-1]
    values = {}
    uniques = {}
    for idx, name in enumerate(header[3:], start=3):
        values[name] = last[idx]
        seen = []
        for row in samples:
            value = row[idx]
            if value not in seen:
                seen.append(value)
        uniques[name] = seen
    return values, uniques, len(samples)


def parse_hex(value):
    return int(value.strip(), 16)


def set_bits(value, width):
    return [idx for idx in range(width) if (value >> idx) & 1]


def find_one(directory, pattern):
    matches = sorted(glob.glob(os.path.join(directory, pattern)))
    if len(matches) != 1:
        raise FileNotFoundError(f"expected one {pattern}, found {len(matches)}")
    return matches[0]


def decode_axis0(path):
    values, uniques, samples = read_last_values(path)
    print(f"axis_ila_0: {path}")
    print(f"  samples={samples}")
    ddr_seen = None
    for name, value in values.items():
        unique = uniques[name]
        unique_desc = ",".join(unique[:4]) + (",..." if len(unique) > 4 else "")
        print(f"  {name}={value} unique={len(unique)} [{unique_desc}]")
        if "ddr_seen16" in name:
            ddr_seen = parse_hex(value)
            print(f"  {name}_bits={set_bits(ddr_seen, 16)}")
            for idx, bit_name in enumerate(DDR_SEEN_BITS):
                print(f"    bit{idx}: {bit_name}={(ddr_seen >> idx) & 1}")
        elif "status16" in name:
            parsed = parse_hex(value)
            print(f"  {name}_bits={set_bits(parsed, 16)}")
    return ddr_seen


def decode_axis1(path):
    values, uniques, samples = read_last_values(path)
    if len(values) != 1:
        raise ValueError(f"expected one axis_ila_1 probe, found {len(values)}")
    name, raw_text = next(iter(values.items()))
    raw = parse_hex(raw_text)

    last_addr = (raw >> 34) & 0x3fffffff
    last_wdata8 = (raw >> 26) & 0xff
    last_rdata8 = (raw >> 18) & 0xff
    last_bresp = (raw >> 16) & 0x3
    last_rresp = (raw >> 14) & 0x3
    flags14 = raw & 0x3fff

    print(f"axis_ila_1 ddr: {path}")
    print(f"  samples={samples} unique={len(uniques[name])}")
    print(f"  {name}=0x{raw:016x}")
    print(f"  last_addr_low=0x{last_addr << 2:08x}")
    print(f"  last_wdata8=0x{last_wdata8:02x}")
    print(f"  last_rdata8=0x{last_rdata8:02x}")
    print(f"  last_bresp=0x{last_bresp:x}")
    print(f"  last_rresp=0x{last_rresp:x}")
    print(f"  flags14=0x{flags14:04x} bits={set_bits(flags14, 14)}")
    return {
        "raw": raw,
        "last_addr_low": last_addr << 2,
        "last_wdata8": last_wdata8,
        "last_rdata8": last_rdata8,
        "last_bresp": last_bresp,
        "last_rresp": last_rresp,
        "flags14": flags14,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 46 debug_build directory")
    args = parser.parse_args()
    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build46_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build46_*axis_ila_1.csv")
        seen = decode_axis0(axis0)
        bus = decode_axis1(axis1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    failures = []
    if seen is None:
        failures.append("DDR seen16 probe missing")
    else:
        for bit, label in [(2, "AW fire"), (4, "W fire"), (6, "B fire"), (9, "AR fire"), (11, "R fire")]:
            if not ((seen >> bit) & 1):
                failures.append(f"{label} was not observed")
        if (seen >> 7) & 1:
            failures.append("DDR write response error observed")
        if (seen >> 12) & 1:
            failures.append("DDR read response error observed")
    if bus["last_bresp"] != 0:
        failures.append("last B response is not OKAY")
    if bus["last_rresp"] != 0:
        failures.append("last R response is not OKAY")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: Build 46 ILA observed DDR write/read AXI handshakes with OKAY responses")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
