#!/usr/bin/env python3
"""Decode Build 70 UART-first and compact SD diagnostic ILA captures."""

import argparse
import csv
import glob
import os
import sys

UART_SEEN_BITS = [
    "core_aw_fire_seen",
    "uart_aw_w_same_cycle_seen",
    "uart_ar_fire_seen",
    "uart_tx_low_seen",
    "uart_noc2_valid_seen",
    "uart_noc3_valid_seen",
    "core_wvalid_seen",
    "test_start_seen",
    "core_w_fire_seen",
    "core_b_fire_seen",
    "core_ar_fire_seen",
    "core_r_fire_seen",
    "uart_aw_fire_seen",
    "uart_w_fire_seen",
    "uart_b_fire_seen",
    "uart_r_fire_seen",
]

UART_FLAGS = [
    "uart_noc3_valid_seen",
    "uart_noc2_valid_seen",
    "test_start_live",
    "uart_tx_transition_seen",
    "uart_tx_low_seen",
    "uart_tx_live",
    "core_b_fire_seen",
    "core_w_fire_seen",
    "core_aw_fire_seen",
    "uart_b_fire_seen",
    "uart_w_fire_seen",
    "uart_aw_fire_seen",
]

SD_FLAGS = [
    "cpu_axi_ar_fire_seen",
    "tm_req_fire_seen",
    "tm_read_error_seen",
    "tm_r_data_bytes_seen",
    "tm_done_seen",
    "axi_sd_resp_fire_seen",
    "axi_r_fire_seen",
    "data_nonzero_seen",
]

CORE_SEEN_BITS = [
    "rst_n_f",
    "spc_grst_l",
    "transducer_l15_val",
    "transducer_l15_req_ack",
    "l15_transducer_val",
    "l15_transducer_ack",
    "processor_router_valid_noc1",
    "processor_router_valid_noc2",
    "processor_router_valid_noc3",
    "buffer_processor_valid_noc1",
    "buffer_processor_valid_noc2",
    "buffer_processor_valid_noc3",
    "router_processor_ready_noc1",
    "router_processor_ready_noc2",
    "router_processor_ready_noc3",
    "l15_transducer_error",
]

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
    "write_addr_0x83_or_0x84_seen",
    "read_addr_0x83_or_0x84_seen",
    "awready_seen",
]

TOP_STATUS_BITS = [
    "chipset_seen_bit12",
    "chipset_seen_bit5",
    "m_axi_bvalid",
    "m_axi_rvalid",
    "m_axi_arvalid",
    "m_axi_awvalid",
    "offchip_processor_noc3_valid",
    "processor_offchip_noc2_valid",
    "uart_rx",
    "uart_tx",
    "uart_rst_out_n",
    "test_start",
    "chipset_rst_n",
    "chip_rst_n",
    "sys_rst_n_rect",
    "sys_rst_n",
]


def read_last_values(path):
    with open(path, newline="") as csv_file:
        rows = list(csv.reader(csv_file))
    if len(rows) < 3:
        raise ValueError(f"CSV has no samples: {path}")
    header = rows[0]
    samples = rows[2:]
    values = {}
    uniques = {}
    for idx, name in enumerate(header[3:], start=3):
        values[name] = samples[-1][idx]
        uniques[name] = list(dict.fromkeys(row[idx] for row in samples))
    return values, uniques, len(samples)


def parse_hex(value):
    return int(value.strip().replace("_", ""), 16)


def set_bits(value, width):
    return [idx for idx in range(width) if (value >> idx) & 1]


def find_one(directory, pattern):
    matches = sorted(glob.glob(os.path.join(directory, pattern)))
    if len(matches) != 1:
        raise FileNotFoundError(f"expected one {pattern}, found {len(matches)}")
    return matches[0]


def print_named_bits(label, value, names):
    print(f"  {label}_bits={set_bits(value, len(names))}")
    for idx, bit_name in enumerate(names):
        print(f"    bit{idx}: {bit_name}={(value >> idx) & 1}")


def summarize_probe(name, value, uniques):
    unique = uniques[name]
    unique_desc = ",".join(unique[:4]) + (",..." if len(unique) > 4 else "")
    print(f"  {name}={value} unique={len(unique)} [{unique_desc}]")


def one_probe_value(path, label):
    values, uniques, samples = read_last_values(path)
    if len(values) != 1:
        raise ValueError(f"expected one {label} probe, found {len(values)} in {path}")
    name, raw_text = next(iter(values.items()))
    raw = parse_hex(raw_text)
    print(f"{label}: {path}")
    print(f"  samples={samples} unique={len(uniques[name])}")
    print(f"  {name}=0x{raw:016x}")
    return raw


def decode_core_bus(path):
    raw = one_probe_value(path, "axis_ila_1 core")
    flags = raw & 0xFF
    print(f"  last_l15_addr=0x{(raw >> 24) & ((1 << 40) - 1):010x}")
    print(f"  last_l15_rqtype=0x{(raw >> 19) & 0x1F:02x}")
    print(f"  last_l15_size=0x{(raw >> 16) & 0x7:x}")
    print(f"  ariane_debug_hi=0x{(raw >> 8) & 0xFF:02x}")
    print(f"  flags=0x{flags:02x} bits={set_bits(flags, 8)}")
    return {"raw": raw, "flags": flags}


def decode_ddr_bus(path):
    raw = one_probe_value(path, "axis_ila_3 ddr")
    decoded = {
        "last_addr_low": ((raw >> 34) & 0x3FFFFFFF) << 2,
        "last_wdata8": (raw >> 26) & 0xFF,
        "last_rdata8": (raw >> 18) & 0xFF,
        "last_bresp": (raw >> 16) & 0x3,
        "last_rresp": (raw >> 14) & 0x3,
        "flags14": raw & 0x3FFF,
    }
    for key, value in decoded.items():
        print(f"  {key}=0x{value:x}")
    return {"raw": raw, **decoded}


def decode_status(path):
    values, uniques, samples = read_last_values(path)
    result = {"core_seen": None, "uart_seen": None, "ddr_seen": None}
    print(f"axis_ila_0 status: {path}")
    print(f"  samples={samples}")
    for name, value in values.items():
        summarize_probe(name, value, uniques)
        parsed = parse_hex(value)
        if "core_seen16" in name:
            result["core_seen"] = parsed
            print_named_bits(name, parsed, CORE_SEEN_BITS)
        elif "uart_seen16" in name:
            result["uart_seen"] = parsed
            print_named_bits(name, parsed, UART_SEEN_BITS)
        elif "ddr_seen16" in name:
            result["ddr_seen"] = parsed
            print_named_bits(name, parsed, DDR_SEEN_BITS)
        elif "top_status16" in name:
            print_named_bits(name, parsed, TOP_STATUS_BITS)
    return result


def decode_uart_sd(path):
    raw = one_probe_value(path, "axis_ila_2 uart_sd")
    sd_flags = (raw >> 56) & 0xFF
    payload = raw & ((1 << 56) - 1)

    decoded = {
        "sd_flags": sd_flags,
        "s_wdata": (payload >> 48) & 0xFF,
        "s_wstrb": (payload >> 44) & 0xF,
        "s_awaddr": (payload >> 36) & 0xFF,
        "core_wdata": (payload >> 28) & 0xFF,
        "core_wstrb": (payload >> 24) & 0xF,
        "core_awaddr": (payload >> 16) & 0xFF,
        "s_bresp": (payload >> 14) & 0x3,
        "core_bresp": (payload >> 12) & 0x3,
        "uart_flags": payload & 0xFFF,
    }

    print(f"  raw=0x{raw:016x}")
    print(f"  sd_flags=0x{sd_flags:02x} bits={set_bits(sd_flags, 8)}")
    for bit, name in enumerate(SD_FLAGS):
        print(f"    sd bit{bit}: {name}={(sd_flags >> bit) & 1}")
    print(
        "  UART last write: core addr=0x%02x data=0x%02x strobe=0x%x bresp=%d; "
        "IP addr=0x%02x data=0x%02x strobe=0x%x bresp=%d"
        % (
            decoded["core_awaddr"],
            decoded["core_wdata"],
            decoded["core_wstrb"],
            decoded["core_bresp"],
            decoded["s_awaddr"],
            decoded["s_wdata"],
            decoded["s_wstrb"],
            decoded["s_bresp"],
        )
    )
    flags = decoded["uart_flags"]
    print(f"  uart_flags=0x{flags:03x} bits={set_bits(flags, 12)}")
    for bit, name in enumerate(UART_FLAGS):
        print(f"    uart bit{bit}: {name}={(flags >> bit) & 1}")
    return decoded


def classify_uart(status, uart):
    seen = status["uart_seen"] or 0
    flags = uart["uart_flags"]

    core_write = all((seen >> bit) & 1 for bit in (0, 8, 9))
    ip_write = all((seen >> bit) & 1 for bit in (12, 13, 14))
    tx_activity = bool((seen >> 3) & 1 or (flags >> 3) & 1 or (flags >> 4) & 1)

    if not ((seen >> 0) & 1):
        return "bootrom UART store did not reach the UART NoC/AXI bridge"
    if not core_write:
        return "UART bridge saw a partial core-side write without a complete OKAY response"
    if not ip_write:
        return "core-side UART write completed but did not complete at the AXI16550 interface"
    if uart["core_bresp"] != 0 or uart["s_bresp"] != 0:
        return "UART write completed with a non-OKAY AXI response"
    if not tx_activity:
        return "AXI16550 write completed but the UART TX signal never toggled low"
    return "AXI16550 write and TX activity are present; inspect baud, pad routing, and capture path"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="Build 70 debug_build directory")
    args = parser.parse_args()

    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build70_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build70_*axis_ila_1.csv")
        axis2 = find_one(args.debug_build_dir, "ila_capture_build70_*axis_ila_2.csv")
        axis3 = find_one(args.debug_build_dir, "ila_capture_build70_*axis_ila_3.csv")
        status = decode_status(axis0)
        core = decode_core_bus(axis1)
        uart = decode_uart_sd(axis2)
        ddr = decode_ddr_bus(axis3)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"DIAG: {classify_uart(status, uart)}")

    failures = []
    if status["core_seen"] is None or not (status["core_seen"] & 0x1):
        failures.append("core reset did not release")
    if not (core["flags"] & 0x04):
        failures.append("core bus reset-release flag is low")
    if ddr["last_bresp"] != 0 or ddr["last_rresp"] != 0:
        failures.append("DDR retained a non-OKAY response")
    if (uart["sd_flags"] >> 2) & 1:
        failures.append("SPI-SD transaction manager reported a read error")

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: Build 70 retained no hard core/DDR/SD error")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
