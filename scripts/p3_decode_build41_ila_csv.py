#!/usr/bin/env python3
"""Decode Build 41 P3 fetch/bootrom ILA CSV captures."""

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
        if len(unique) <= 4:
            unique_desc = ",".join(unique)
        else:
            unique_desc = ",".join(unique[:4]) + ",..."
        print(f"  {name}={value} unique={len(unique)} [{unique_desc}]")

    top_status = None
    chipset_seen = None
    chip_seen = None
    for name, value in values.items():
        if "p3_dbg_top_status16" in name:
            top_status = parse_hex(value)
        elif "p3_dbg_uart_seen16" in name:
            chipset_seen = parse_hex(value)
        elif "p3_dbg_chip_seen16" in name:
            chip_seen = parse_hex(value)
    if top_status is not None:
        print(f"  top_status_bits={set_bits(top_status, 16)}")
    if chipset_seen is not None:
        print(f"  chipset_seen_bits={set_bits(chipset_seen, 16)}")
    if chip_seen is not None:
        print(f"  chip_tile_seen_bits={set_bits(chip_seen, 16)}")


def decode_core(path):
    values, uniques, samples = read_last_values(path)
    value = parse_hex(next(iter(values.values())))
    addr = (((value >> 48) & 0xffff) << 24) | (((value >> 32) & 0xffff) << 8) | ((value >> 24) & 0xff)
    rqtype = (value >> 19) & 0x1f
    size = (value >> 16) & 0x7
    ariane = (value >> 8) & 0xff
    l15 = value & 0xff

    print(f"axis_ila_1 core: {path}")
    print(f"  samples={samples} unique={len(next(iter(uniques.values())))}")
    print(f"  raw=0x{value:016x}")
    print(f"  last_l15_addr_40=0x{addr:010x}")
    print(f"  last_l15_rqtype=0x{rqtype:x} last_l15_size=0x{size:x}")
    print(f"  ariane_flags=0x{ariane:02x} bits={set_bits(ariane, 8)}")
    print("    bit7 wake_high, bit6 ariane_rst_n, bit5 spc_grst_l, bit4 reset_l")
    print("    bit3 debug_req, bit2 time_irq, bit1 ipi, bit0 irq")
    print(f"  l15_flags=0x{l15:02x} bits={set_bits(l15, 8)}")
    print("    bit7 l15_req_val, bit6 l15_req_ack, bit5 l15_ret_val, bit4 l15_ret_ack")
    print("    bit3 l15_error, bit2 tile_rst_n, bit1 spc_grst_l, bit0 clk_en")


def decode_chipset(path):
    values, uniques, samples = read_last_values(path)
    value = parse_hex(next(iter(values.values())))
    intf_data = (value >> 48) & 0xffff
    boot_req = (value >> 32) & 0xffff
    boot_resp = (value >> 16) & 0xffff
    flags = value & 0xffff
    flag_names = [
        "uart_activity_seen",
        "ariane_boot_sel",
        "cpu_mem_traffic",
        "invalid_access",
        "mem_axi_addr_valid",
        "uart_buf_noc2_ready",
        "buf_uart_noc2_valid",
        "buf_ariane_bootrom_noc3_ready",
        "ariane_bootrom_buf_noc3_valid",
        "ariane_bootrom_buf_noc2_ready",
        "buf_ariane_bootrom_noc2_valid",
        "filter_chip_noc2_ready",
        "chip_filter_noc2_valid",
        "intf_chipset_rdy_noc2",
        "intf_chipset_val_noc2",
        "chipset_rst_n",
    ]

    print(f"axis_ila_2 chipset: {path}")
    print(f"  samples={samples} unique={len(next(iter(uniques.values())))}")
    print(f"  raw=0x{value:016x}")
    print(f"  last_intf_chipset_data_noc2_low16=0x{intf_data:04x}")
    print(f"  last_bootrom_req_data_low16=0x{boot_req:04x}")
    print(f"  last_bootrom_resp_data_low16=0x{boot_resp:04x}")
    print(f"  sticky_flags=0x{flags:04x} bits={set_bits(flags, 16)}")
    for idx, name in enumerate(flag_names):
        print(f"    bit{idx}: {name}={(flags >> idx) & 1}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 41 debug_build directory")
    args = parser.parse_args()

    directory = args.debug_build_dir
    try:
        axis0 = find_one(directory, "ila_capture_build41_*axis_ila_0.csv")
        axis1 = find_one(directory, "ila_capture_build41_*axis_ila_1.csv")
        axis2 = find_one(directory, "ila_capture_build41_*axis_ila_2.csv")
        decode_axis0(axis0)
        decode_core(axis1)
        decode_chipset(axis2)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
