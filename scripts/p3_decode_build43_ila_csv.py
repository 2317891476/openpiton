#!/usr/bin/env python3
"""Decode Build 43 no-stack AXI16550 UART ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


STATUS_BITS = [
    "rst_seen",
    "init_or_status",
    "banner_or_tx",
    "uart_tx_low_seen",
    "core_r_fire_seen",
    "core_ar_fire_seen",
    "core_b_fire_seen",
    "core_w_fire_seen",
    "test_start",
    "core_wvalid_seen",
    "uart_noc3_valid_seen",
    "uart_noc2_valid_seen",
    "uart_tx_low_live",
    "uart_ar_fire_seen",
    "uart_aw_w_same_cycle_seen",
    "core_aw_fire_seen",
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
    for name, value in values.items():
        unique = uniques[name]
        unique_desc = ",".join(unique[:4]) + (",..." if len(unique) > 4 else "")
        print(f"  {name}={value} unique={len(unique)} [{unique_desc}]")
        if "status16" in name or "seen16" in name:
            parsed = parse_hex(value)
            print(f"  {name}_bits={set_bits(parsed, 16)}")


def decode_uart(path):
    values, uniques, samples = read_last_values(path)
    if len(values) != 1:
        raise ValueError(f"expected one axis_ila_1 probe, found {len(values)}")
    name, raw_text = next(iter(values.items()))
    raw = parse_hex(raw_text)

    s_wdata = (raw >> 48) & 0xff
    s_wstrb = (raw >> 44) & 0xf
    s_awaddr_low = (raw >> 36) & 0xff
    core_wdata = (raw >> 28) & 0xff
    core_wstrb = (raw >> 24) & 0xf
    core_awaddr_low = (raw >> 16) & 0xff
    s_bresp = (raw >> 14) & 0x3
    core_bresp = (raw >> 12) & 0x3
    flags = raw & 0xfff
    flag_names = [
        "uart_noc3_valid_seen",
        "uart_noc2_valid_seen",
        "test_start_live",
        "uart_aw_or_w_fire_live",
        "uart_tx_low_seen",
        "uart_tx_live",
        "core_b_fire_seen",
        "core_w_fire_seen",
        "core_aw_fire_seen",
        "uart_b_fire_seen",
        "uart_w_fire_seen",
        "uart_aw_fire_seen",
    ]

    print(f"axis_ila_1 uart: {path}")
    print(f"  samples={samples} unique={len(uniques[name])}")
    print(f"  {name}=0x{raw:016x}")
    print(f"  s_axi_wdata=0x{s_wdata:02x} ({chr(s_wdata) if 32 <= s_wdata < 127 else '.'})")
    print(f"  s_axi_wstrb=0x{s_wstrb:x}")
    print(f"  s_axi_awaddr_low=0x{s_awaddr_low:02x}")
    print(f"  core_axi_wdata=0x{core_wdata:02x} ({chr(core_wdata) if 32 <= core_wdata < 127 else '.'})")
    print(f"  core_axi_wstrb=0x{core_wstrb:x}")
    print(f"  core_axi_awaddr_low=0x{core_awaddr_low:02x}")
    print(f"  s_axi_bresp=0x{s_bresp:x}")
    print(f"  core_axi_bresp=0x{core_bresp:x}")
    print(f"  flags=0x{flags:03x} bits={set_bits(flags, 12)}")
    for idx, flag_name in enumerate(flag_names):
        print(f"    bit{idx}: {flag_name}={(flags >> idx) & 1}")

    failures = []
    if s_wstrb != 0x1:
        failures.append("UART-side write strobe is not byte lane 0")
    if core_wstrb != 0x1:
        failures.append("core-side write strobe is not byte lane 0")
    if s_bresp != 0 or core_bresp != 0:
        failures.append("AXI write response is not OKAY")
    if not (flags & (1 << 11)):
        failures.append("UART-side AW fire sticky bit not set")
    if not (flags & (1 << 10)):
        failures.append("UART-side W fire sticky bit not set")
    if not (flags & (1 << 9)):
        failures.append("UART-side B fire sticky bit not set")
    if not (flags & (1 << 8)):
        failures.append("core AW fire sticky bit not set")
    if not (flags & (1 << 7)):
        failures.append("core W fire sticky bit not set")
    if not (flags & (1 << 6)):
        failures.append("core B fire sticky bit not set")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: Build 43 ILA shows AXI16550 write path activity and OKAY responses")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 43 debug_build directory")
    args = parser.parse_args()
    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build43_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build43_*axis_ila_1.csv")
        decode_axis0(axis0)
        return decode_uart(axis1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
