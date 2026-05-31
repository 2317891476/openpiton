#!/usr/bin/env python3
"""Decode Build 42-A no-stack ASM UART ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


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
    for name, value in values.items():
        unique = uniques[name]
        unique_desc = ",".join(unique[:4]) + (",..." if len(unique) > 4 else "")
        print(f"  {name}={value} unique={len(unique)} [{unique_desc}]")
    for name, value in values.items():
        if "status16" in name or "seen16" in name:
            parsed = parse_hex(value)
            print(f"  {name}_bits={set_bits(parsed, 16)}")


def decode_uart(path):
    values, uniques, samples = read_last_values(path)
    value = parse_hex(next(iter(values.values())))
    last_addr = (value >> 56) & 0xff
    last_wdata = (value >> 48) & 0xff
    last_rdata = (value >> 40) & 0xff
    last_wstrb = (value >> 36) & 0xf
    flags = (value >> 24) & 0xfff
    reserved = value & 0xffffff
    flag_names = [
        "ip2intc_irpt",
        "tx_transition_seen",
        "tx_low_seen",
        "uart_tx",
        "tl_d_valid",
        "tl_a_ready",
        "tl_a_valid",
        "s_axi_rvalid",
        "s_axi_bvalid",
        "ar_pending",
        "w_pending",
        "aw_pending",
    ]

    print(f"axis_ila_1 uart: {path}")
    print(f"  samples={samples} unique={len(next(iter(uniques.values())))}")
    print(f"  raw=0x{value:016x}")
    print(f"  last_addr_low8=0x{last_addr:02x}")
    print(f"  last_wdata_low8=0x{last_wdata:02x}")
    print(f"  last_rdata_low8=0x{last_rdata:02x}")
    print(f"  last_wstrb=0x{last_wstrb:x}")
    print(f"  uart_flags=0x{flags:03x} bits={set_bits(flags, 12)}")
    for idx, name in enumerate(flag_names):
        print(f"    bit{idx}: {name}={(flags >> idx) & 1}")
    print(f"  reserved_low24=0x{reserved:06x}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 42-A debug_build directory")
    args = parser.parse_args()
    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build42a_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build42a_*axis_ila_1.csv")
        decode_axis0(axis0)
        decode_uart(axis1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
