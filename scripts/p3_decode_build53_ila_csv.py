#!/usr/bin/env python3
"""Decode Build 53 SD command-layer ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


SD_CMD_SEEN_BITS = [
    "wb_reset_released_seen",
    "cmd_index_55_seen",
    "cmd_timeout_nonzero_seen",
    "cmd_interrupt_enable0_seen",
    "cmd_start_wb_seen",
    "cmd_start_sd_seen",
    "cmd_start_tx_seen",
    "cmd_finish_seen",
    "cmd_int_cc_seen",
    "cmd_int_ei_seen",
    "cmd_int_cte_seen",
    "sd_int_cmd_seen",
    "cmd_oe_seen",
    "cmd_line_low_seen",
    "cmd_master_execute_seen",
    "cmd_serial_read_wait_seen",
]

CMD_INT_BITS = [
    "CC_complete",
    "EI_error",
    "CTE_timeout",
    "CCRCE_crc_error",
    "CIE_index_error",
]

CMD_FLAGS = [
    "sd_int_cmd",
    "cmd_oe_o",
    "sd_cmd_dat_i",
    "cmd_finish",
    "cmd_start_tx",
    "cmd_start_sd",
    "cmd_start_wb",
]

MASTER_STATES = {
    0: "IDLE",
    1: "EXECUTE",
    2: "BUSY_CHECK",
}

SERIAL_STATES = {
    0x00: "INIT",
    0x01: "IDLE",
    0x02: "SETUP_CRC",
    0x04: "WRITE",
    0x08: "READ_WAIT",
    0x10: "READ",
    0x20: "FINISH_WR",
    0x40: "FINISH_WO",
}

INIT_STATES = {
    0x34: "ST_ACMD41_CMD55_WAIT_INT",
    0x35: "ST_ACMD41_CMD55_RD_CMD_ISR",
    0x36: "ST_ACMD41_CMD55_RD_RESP0",
    0x44: "ST_ACMD41_WAIT_INT",
    0x47: "ST_ACMD41_WAIT_INTERVAL",
    0xF0: "ST_INIT_DONE",
}


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
    return int(value.strip().replace("_", "").removeprefix("0x"), 16)


def set_bits(value, width):
    return [idx for idx in range(width) if (value >> idx) & 1]


def print_bits(label, value, names):
    print(f"  {label}=0x{value:0{max(1, (len(names) + 3) // 4)}x} bits={set_bits(value, len(names))}")
    for idx, name in enumerate(names):
        print(f"    bit{idx}: {name}={(value >> idx) & 1}")


def find_one(directory, pattern):
    matches = sorted(glob.glob(os.path.join(directory, pattern)))
    if len(matches) != 1:
        raise FileNotFoundError(f"expected one {pattern}, found {len(matches)}")
    return matches[0]


def decode_axis0(path):
    values, uniques, samples = read_last_values(path)
    print(f"axis_ila_0 status: {path}")
    print(f"  samples={samples}")
    status = {}
    for name, text in values.items():
        value = parse_hex(text)
        unique = uniques[name]
        print(f"  {name}={text} unique={len(unique)}")
        if "uart_seen16" in name:
            status["sd_cmd_seen"] = value
            print_bits(name, value, SD_CMD_SEEN_BITS)
        elif "core_seen16" in name:
            status["core_seen"] = value
        elif "top_status16" in name:
            status["top_status"] = value
    return status


def one_probe(path, label):
    values, uniques, samples = read_last_values(path)
    if len(values) != 1:
        raise ValueError(f"expected one {label} probe, found {len(values)}")
    name, text = next(iter(values.items()))
    raw = parse_hex(text)
    print(f"{label}: {path}")
    print(f"  samples={samples} unique={len(uniques[name])}")
    print(f"  {name}=0x{raw:016x}")
    return raw, len(uniques[name])


def decode_sd_cmd(path):
    raw, unique = one_probe(path, "axis_ila_2 sd_cmd")
    init_state = (raw >> 56) & 0xFF
    watchdog_low = (raw >> 48) & 0xFF
    cmd_index = (raw >> 42) & 0x3F
    cmd_int_sd = (raw >> 37) & 0x1F
    cmd_int_wb = (raw >> 32) & 0x1F
    cmd_timeout = (raw >> 16) & 0xFFFF
    master_state = (raw >> 14) & 0x3
    serial_state = (raw >> 7) & 0x7F
    flags = raw & 0x7F

    print(f"  init_state=0x{init_state:02x} {INIT_STATES.get(init_state, 'unknown')}")
    print(f"  watchdog_low=0x{watchdog_low:02x}")
    print(f"  command_index_sd={cmd_index}")
    print_bits("cmd_int_status_sd", cmd_int_sd, CMD_INT_BITS)
    print_bits("cmd_int_status_wb", cmd_int_wb, CMD_INT_BITS)
    print(f"  cmd_timeout_low16=0x{cmd_timeout:04x}")
    print(f"  cmd_master_state={master_state} {MASTER_STATES.get(master_state, 'unknown')}")
    print(f"  cmd_serial_state=0x{serial_state:02x} {SERIAL_STATES.get(serial_state, 'unknown')}")
    print_bits("flags", flags, CMD_FLAGS)

    return {
        "raw": raw,
        "unique": unique,
        "init_state": init_state,
        "watchdog_low": watchdog_low,
        "cmd_index": cmd_index,
        "cmd_int_sd": cmd_int_sd,
        "cmd_int_wb": cmd_int_wb,
        "cmd_timeout": cmd_timeout,
        "master_state": master_state,
        "serial_state": serial_state,
        "flags": flags,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 53 debug_build directory")
    args = parser.parse_args()

    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build53_*axis_ila_0.csv")
        axis2 = find_one(args.debug_build_dir, "ila_capture_build53_*axis_ila_2.csv")
        status = decode_axis0(axis0)
        sd = decode_sd_cmd(axis2)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    warnings = []
    failures = []
    seen = status.get("sd_cmd_seen", 0)

    if not (seen & (1 << 4)):
        failures.append("CMD start was not observed in the Wishbone clock domain")
    if not (seen & (1 << 5)):
        failures.append("CMD start was not observed in the SD clock domain")
    if not (seen & (1 << 6)):
        failures.append("serial command transfer start was not observed")
    if not (seen & (1 << 2)):
        warnings.append("cmd_timeout register was never observed nonzero")

    if sd["init_state"] == 0x34:
        if sd["master_state"] == 1 and sd["serial_state"] == 0x08:
            failures.append("CMD55 is active but the serial host is waiting for a response start bit on CMD")
        elif sd["master_state"] == 1 and not (sd["cmd_int_sd"] & 0x04):
            warnings.append("CMD master is still executing without a timeout status")
        elif sd["cmd_int_sd"] and not (sd["flags"] & 0x01):
            failures.append("CMD interrupt status exists in SD clock domain but int_cmd is low in WB domain")
    if sd["cmd_timeout"] == 0:
        failures.append("current cmd_timeout register is zero")
    if sd["cmd_index"] != 55 and sd["init_state"] == 0x34:
        warnings.append("init FSM waits for CMD55, but current SD command index is not 55")
    if sd["unique"] > 8 and sd["master_state"] == 1:
        warnings.append("SD command debug bus is still changing during capture, likely watchdog or command activity is live")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    if warnings:
        print("WARN:")
        for warning in warnings:
            print(f"  - {warning}")

    print("PASS: Build 53 SD command debug decode completed without hard failures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
