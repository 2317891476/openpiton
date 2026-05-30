#!/usr/bin/env python3
"""Decode standalone P3 AXI UART16550 ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


STATUS_BITS = [
    "rst_seen",
    "init_done",
    "banner_done",
    "tx_write_seen",
    "rx_read_seen",
    "rx_byte_seen",
    "rx_falling_seen",
    "tx_low_seen",
    "tx_transition_seen",
    "axi_b_error",
    "axi_r_error",
    "lsr_dr_seen",
    "lsr_thre_seen",
    "op_busy",
    "uart_rx",
    "uart_tx",
]

FLAG_BITS = [
    "uart_tx",
    "uart_rx",
    "s_axi_rvalid",
    "s_axi_bvalid",
    "op_busy",
    "op_write_q",
    "r_fire",
    "ar_fire",
    "b_fire",
    "w_fire",
    "aw_fire",
    "r_fire_seen",
    "ar_fire_seen",
    "b_fire_seen",
    "w_fire_seen",
    "aw_fire_seen",
]


def parse_hex(value):
    value = value.strip()
    if value.startswith("0x"):
        return int(value, 16)
    return int(value, 16)


def read_csv(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 3:
        raise ValueError(f"CSV has no samples: {path}")
    header = rows[0]
    samples = rows[2:]
    values = {}
    uniques = {}
    for idx, name in enumerate(header[3:], start=3):
        col = [row[idx] for row in samples]
        values[name] = col[-1]
        uniques[name] = sorted(set(col))
    return values, uniques, len(samples)


def find_signal(values, needle):
    matches = [name for name in values if needle in name]
    if not matches:
        raise KeyError(f"missing signal containing {needle!r}; available: {list(values)}")
    return matches[0], parse_hex(values[matches[0]])


def bit_names(value, names):
    return [name for idx, name in enumerate(names) if (value >> idx) & 1]


def decode(path):
    values, uniques, samples = read_csv(path)
    print(f"CSV: {path}")
    print(f"samples={samples}")

    status_name, status = find_signal(values, "p3_uart_status_i")
    txn_name, txn = find_signal(values, "p3_uart_txn_i")
    counts_name, counts = find_signal(values, "p3_uart_counts_i")
    rx_level_name, rx_level = find_signal(values, "p3_uart_rx_level_i")
    rx_fall_name, rx_fall = find_signal(values, "p3_uart_rx_fall_i")

    ctrl_state = (txn >> 56) & 0xff
    last_addr_low = (txn >> 48) & 0xff
    last_wdata = (txn >> 40) & 0xff
    last_rdata = (txn >> 32) & 0xff
    last_lsr = (txn >> 24) & 0xff
    last_rx_byte = (txn >> 16) & 0xff
    flags = txn & 0xffff
    tx_count = (counts >> 16) & 0xffff
    rx_count = counts & 0xffff

    print(f"{status_name}=0x{status:04x}")
    print(f"  set={bit_names(status, STATUS_BITS)}")
    print(f"{txn_name}=0x{txn:016x}")
    print(f"  ctrl_state={ctrl_state}")
    print(f"  last_addr_low=0x{last_addr_low:02x}")
    print(f"  last_wdata=0x{last_wdata:02x} ({chr(last_wdata) if 32 <= last_wdata < 127 else '.'})")
    print(f"  last_rdata=0x{last_rdata:02x} ({chr(last_rdata) if 32 <= last_rdata < 127 else '.'})")
    print(f"  last_lsr=0x{last_lsr:02x}")
    print(f"  last_rx_byte=0x{last_rx_byte:02x} ({chr(last_rx_byte) if 32 <= last_rx_byte < 127 else '.'})")
    print(f"  flags=0x{flags:04x} set={bit_names(flags, FLAG_BITS)}")
    print(f"{counts_name}=0x{counts:08x} tx_count={tx_count} rx_count={rx_count}")
    print(f"{rx_level_name}=0x{rx_level:x} unique={uniques[rx_level_name]}")
    print(f"{rx_fall_name}=0x{rx_fall:x} unique={uniques[rx_fall_name]}")

    failures = []
    if not (status & (1 << STATUS_BITS.index("init_done"))):
        failures.append("init_done is not set")
    if not (status & (1 << STATUS_BITS.index("banner_done"))):
        failures.append("banner_done is not set")
    if not (status & (1 << STATUS_BITS.index("rx_read_seen"))):
        failures.append("rx_read_seen is not set")
    if not (status & (1 << STATUS_BITS.index("tx_write_seen"))):
        failures.append("tx_write_seen is not set")
    if status & ((1 << STATUS_BITS.index("axi_b_error")) | (1 << STATUS_BITS.index("axi_r_error"))):
        failures.append("AXI error sticky bit is set")
    if rx_count == 0:
        failures.append("rx_count is zero")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: ILA shows initialized UART16550, RX read, TX write, and no AXI error")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="huaprop3_uart16550_ila_interact/debug_build")
    args = parser.parse_args()
    matches = sorted(glob.glob(os.path.join(args.debug_build_dir, "ila_capture_uart16550_*.csv")))
    if len(matches) != 1:
        print(f"ERROR: expected one ila_capture_uart16550_*.csv, found {len(matches)}", file=sys.stderr)
        return 1
    try:
        return decode(matches[0])
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
