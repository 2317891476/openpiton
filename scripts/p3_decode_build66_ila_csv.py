#!/usr/bin/env python3
"""Decode Build 66 normal SPI-SD boot ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


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

BLOCK_SEEN_BITS = [
    "reset_released",
    "axi_ar_fire_seen",
    "axi_sd_req_fire_seen",
    "tm_req_fire_seen",
    "tm_w_trans_type_seen",
    "tm_w_trans_ctrl_seen",
    "tm_r_trans_status_done_seen",
    "tm_r_trans_err_seen",
    "tm_read_error_seen",
    "tm_r_data_bytes_seen",
    "tm_cache_w_en_seen",
    "tm_done_seen",
    "axi_sd_resp_fire_seen",
    "axi_send_resp_seen",
    "axi_r_fire_seen",
    "data_nonzero_seen",
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

AXI_STATES = {
    0: "RESET",
    1: "RDY",
    2: "INIT_REQ",
    3: "WRITEBACK_START",
    4: "WRITEBACK_WAIT",
    5: "READ_START",
    6: "READ_WAIT",
    7: "COMPLETE_REQ",
    8: "SEND_RESP",
    9: "COMPLETE_REQ_WR",
}

TM_STATES = {
    0: "RS_CLEAR",
    1: "RS_WAIT",
    2: "RS_W_TRANS_TYPE",
    3: "RS_W_TRANS_CTRL",
    4: "RS_R_TRANS_STS",
    5: "RS_R_TRANS_ERR",
    6: "RDY",
    7: "W_ADDR_0",
    8: "W_ADDR_1",
    9: "W_ADDR_2",
    10: "W_ADDR_3",
    11: "W_DATA_BYTES",
    12: "W_TRANS_TYPE",
    13: "W_TRANS_CTRL",
    14: "R_TRANS_STS",
    15: "R_TRANS_ERR",
    16: "R_DATA_BYTES",
    17: "DONE",
    18: "W_DATA_WORD",
    19: "R_DATA_WORD",
    26: "W_CLEAR_FIFO",
    31: "WB_CHILL",
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
    text = value.strip().replace("_", "")
    if text.startswith(("0x", "0X")):
        return int(text, 16)
    return int(text, 16)


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


def decode_axis0(path):
    values, uniques, samples = read_last_values(path)
    result = {
        "top_status": None,
        "core_seen": None,
        "block_seen": None,
        "ddr_seen": None,
    }
    print(f"axis_ila_0 status/block: {path}")
    print(f"  samples={samples}")
    for name, value in values.items():
        summarize_probe(name, value, uniques)
        parsed = parse_hex(value)
        if "top_status16" in name:
            result["top_status"] = parsed
            print_named_bits(name, parsed, TOP_STATUS_BITS)
        elif "core_seen16" in name:
            result["core_seen"] = parsed
            print_named_bits(name, parsed, CORE_SEEN_BITS)
        elif "uart_seen16" in name:
            result["block_seen"] = parsed
            print_named_bits(name, parsed, BLOCK_SEEN_BITS)
        elif "ddr_seen16" in name:
            result["ddr_seen"] = parsed
            print_named_bits(name, parsed, DDR_SEEN_BITS)
        elif "heartbeat" in name:
            print(f"  {name}_heartbeat_last={parsed}")
    return result


def decode_core_bus(path):
    raw = one_probe_value(path, "axis_ila_1 core")
    last_l15_addr = (raw >> 24) & ((1 << 40) - 1)
    rqtype = (raw >> 19) & 0x1F
    size = (raw >> 16) & 0x7
    ariane_debug_hi = (raw >> 8) & 0xFF
    flags = raw & 0xFF
    print(f"  last_l15_addr=0x{last_l15_addr:010x}")
    print(f"  last_l15_rqtype=0x{rqtype:02x}")
    print(f"  last_l15_size=0x{size:x}")
    print(f"  ariane_debug_hi=0x{ariane_debug_hi:02x}")
    print(f"  flags=0x{flags:02x} bits={set_bits(flags, 8)}")
    return {
        "raw": raw,
        "last_l15_addr": last_l15_addr,
        "rqtype": rqtype,
        "size": size,
        "flags": flags,
    }


def decode_block_bus(path):
    raw = one_probe_value(path, "axis_ila_2 spi_sd_block")
    tm_debug = raw & 0xFFFFFFFF
    decoded = {
        "raw": raw,
        "axi_state": (raw >> 60) & 0xF,
        "axi_state_seen": (raw >> 50) & 0x3FF,
        "valid_match_nonzero": (raw >> 49) & 0x1,
        "selected_block_valid": (raw >> 48) & 0x1,
        "sd_resp_succ": (raw >> 47) & 0x1,
        "last_axi_rdata8": (raw >> 39) & 0xFF,
        "last_raddr_low7": (raw >> 32) & 0x7F,
        "tm_state": (tm_debug >> 27) & 0x1F,
        "tm_after_state": (tm_debug >> 22) & 0x1F,
        "tm_wcntr": (tm_debug >> 15) & 0x7F,
        "tm_bcntr": (tm_debug >> 12) & 0x7,
        "tm_last_dat_i": (tm_debug >> 4) & 0xFF,
        "tm_succ": (tm_debug >> 3) & 0x1,
        "tm_resp_val": (tm_debug >> 2) & 0x1,
        "tm_req_rdy": (tm_debug >> 1) & 0x1,
        "tm_done_seen": tm_debug & 0x1,
    }

    print(f"  axi_state=0x{decoded['axi_state']:x} ({AXI_STATES.get(decoded['axi_state'], 'UNKNOWN')})")
    print(f"  axi_state_seen=0x{decoded['axi_state_seen']:03x}")
    for bit in range(10):
        if (decoded["axi_state_seen"] >> bit) & 1:
            print(f"    axi_state_seen[{bit:02d}]={AXI_STATES.get(bit, 'UNKNOWN')}")
    print(
        "  axi_flags: valid_match=%d selected_valid=%d sd_resp_succ=%d "
        "last_rdata8=0x%02x last_raddr_low7=0x%02x"
        % (
            decoded["valid_match_nonzero"],
            decoded["selected_block_valid"],
            decoded["sd_resp_succ"],
            decoded["last_axi_rdata8"],
            decoded["last_raddr_low7"],
        )
    )
    print(
        "  tm_state=0x%02x (%s) after=0x%02x (%s) wcntr=%d bcntr=%d"
        % (
            decoded["tm_state"],
            TM_STATES.get(decoded["tm_state"], "UNKNOWN"),
            decoded["tm_after_state"],
            TM_STATES.get(decoded["tm_after_state"], "UNKNOWN"),
            decoded["tm_wcntr"],
            decoded["tm_bcntr"],
        )
    )
    print(
        "  tm_flags: last_dat_i=0x%02x succ=%d resp_val=%d req_rdy=%d done_seen=%d"
        % (
            decoded["tm_last_dat_i"],
            decoded["tm_succ"],
            decoded["tm_resp_val"],
            decoded["tm_req_rdy"],
            decoded["tm_done_seen"],
        )
    )
    return decoded


def decode_ddr_bus(path):
    raw = one_probe_value(path, "axis_ila_3 ddr")
    last_addr = (raw >> 34) & 0x3FFFFFFF
    last_wdata8 = (raw >> 26) & 0xFF
    last_rdata8 = (raw >> 18) & 0xFF
    last_bresp = (raw >> 16) & 0x3
    last_rresp = (raw >> 14) & 0x3
    flags14 = raw & 0x3FFF
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
    parser.add_argument("debug_build_dir", help="Build 66 debug_build directory")
    args = parser.parse_args()

    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build66_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build66_*axis_ila_1.csv")
        axis2 = find_one(args.debug_build_dir, "ila_capture_build66_*axis_ila_2.csv")
        axis3 = find_one(args.debug_build_dir, "ila_capture_build66_*axis_ila_3.csv")
        status = decode_axis0(axis0)
        core = decode_core_bus(axis1)
        block = decode_block_bus(axis2)
        ddr = decode_ddr_bus(axis3)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    failures = []
    warnings = []

    if status["core_seen"] is not None:
        if not ((status["core_seen"] >> 0) & 1):
            failures.append("tile reset rst_n_f did not release")
        if (status["core_seen"] >> 15) & 1:
            failures.append("L15 error observed")

    seen = status["block_seen"]
    if seen is None:
        failures.append("Build 66 SPI-SD block seen16 probe missing")
    else:
        required = {
            1: "CPU/NoC did not issue an AXI SD read",
            2: "axi_sd_bridge did not launch an SD block request",
            3: "transaction manager did not accept the SD block request",
            6: "block transaction status never completed",
            9: "RX FIFO bytes were not copied",
            10: "cache line was not written from RX data",
            12: "axi_sd_bridge did not receive transaction-manager response",
            14: "AXI read response did not fire back to NoC",
        }
        for bit, message in required.items():
            if not ((seen >> bit) & 1):
                failures.append(message)
        if (seen >> 8) & 1:
            failures.append("transaction manager reported a read error")
        if not ((seen >> 15) & 1):
            warnings.append("block-read data looked all-zero in the observed low byte")

    if block["tm_succ"] == 0:
        failures.append("transaction-manager success flag is low")
    if block["sd_resp_succ"] == 0 and ((seen or 0) >> 12) & 1:
        failures.append("axi_sd_bridge saw a response but sd_resp_succ is low")
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

    print("PASS: Build 66 SPI-SD/DDR ILA decode completed without hard failures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
