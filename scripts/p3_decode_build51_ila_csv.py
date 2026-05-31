#!/usr/bin/env python3
"""Decode Build 51 SD init debug ILA CSV captures."""

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

SD_INIT_SEEN_BITS = [
    "sys_rst_released_seen",
    "sd_cd_high_seen",
    "sd_cd_low_seen",
    "sd_rst_high_seen",
    "sd_rst_low_seen",
    "init_done_seen",
    "wb_stb_seen",
    "wb_we_seen",
    "wb_ack_seen",
    "sd_int_cmd_seen",
    "sd_int_data_seen",
    "sd_clk_toggle_seen",
    "sd_cmd_oe_seen",
    "sd_dat_oe_seen",
    "sd_cmd_low_seen",
    "sd_dat0_low_seen",
]

SD_INIT_FLAGS_BITS = [
    "sys_rst",
    "sd_cd",
    "sd_rst",
    "init_done",
    "is_hcxc",
    "wb_stb",
    "wb_we",
    "wb_ack",
    "sd_int_cmd",
    "sd_int_data",
    "sd_clk_out",
    "sd_clk_toggle",
    "sd_cmd_dat_i",
    "sd_cmd_out_o",
    "sd_cmd_oe_o",
    "sd_dat_oe_o",
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


def decode_axis0(path):
    values, uniques, samples = read_last_values(path)
    result = {
        "top_status": None,
        "core_seen": None,
        "sd_seen": None,
        "ddr_seen": None,
    }
    print(f"axis_ila_0 status: {path}")
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
            result["sd_seen"] = parsed
            print_named_bits(name, parsed, SD_INIT_SEEN_BITS)
        elif "ddr_seen16" in name:
            result["ddr_seen"] = parsed
            print_named_bits(name, parsed, DDR_SEEN_BITS)
        elif "heartbeat" in name:
            print(f"  {name}_heartbeat_last={parsed}")
    return result


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
    last_l15_addr = (raw >> 24) & ((1 << 40) - 1)
    rqtype = (raw >> 19) & 0x1f
    size = (raw >> 16) & 0x7
    ariane_debug_hi = (raw >> 8) & 0xff
    flags = raw & 0xff
    print(f"  last_l15_addr=0x{last_l15_addr:010x}")
    print(f"  last_l15_rqtype=0x{rqtype:02x}")
    print(f"  last_l15_size=0x{size:x}")
    print(f"  ariane_debug_hi=0x{ariane_debug_hi:02x}")
    print("  flags:")
    for idx, bit_name in enumerate([
        "clk_en",
        "spc_grst_l",
        "rst_n_f",
        "l15_error",
        "l15_transducer_ack",
        "l15_transducer_val",
        "transducer_l15_req_ack",
        "transducer_l15_val",
    ]):
        print(f"    bit{idx}: {bit_name}={(flags >> idx) & 1}")
    return {
        "raw": raw,
        "last_l15_addr": last_l15_addr,
        "rqtype": rqtype,
        "size": size,
        "flags": flags,
    }


def decode_sd_init_debug_bus(path):
    raw = one_probe_value(path, "axis_ila_2 sd_init_debug")
    decoded = {
        "init_state": (raw >> 56) & 0xff,
        "counter_hi": (raw >> 48) & 0xff,
        "wb_adr": (raw >> 40) & 0xff,
        "wb_dat_i_low": (raw >> 32) & 0xff,
        "wb_dat_o_low": (raw >> 24) & 0xff,
        "sd_dat_i": (raw >> 20) & 0xf,
        "sd_dat_o": (raw >> 16) & 0xf,
        "flags16": raw & 0xffff,
    }
    for key, value in decoded.items():
        width = 4 if key == "flags16" else 2
        print(f"  {key}=0x{value:0{width}x}")
    print_named_bits("flags16", decoded["flags16"], SD_INIT_FLAGS_BITS)
    return {"raw": raw, **decoded}


def decode_ddr_bus(path):
    raw = one_probe_value(path, "axis_ila_3 ddr")
    last_addr = (raw >> 34) & 0x3fffffff
    last_wdata8 = (raw >> 26) & 0xff
    last_rdata8 = (raw >> 18) & 0xff
    last_bresp = (raw >> 16) & 0x3
    last_rresp = (raw >> 14) & 0x3
    flags14 = raw & 0x3fff
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
    parser.add_argument("debug_build_dir", help="Build 51 debug_build directory")
    args = parser.parse_args()
    try:
        axis0 = find_one(args.debug_build_dir, "ila_capture_build51_*axis_ila_0.csv")
        axis1 = find_one(args.debug_build_dir, "ila_capture_build51_*axis_ila_1.csv")
        axis2 = find_one(args.debug_build_dir, "ila_capture_build51_*axis_ila_2.csv")
        axis3 = find_one(args.debug_build_dir, "ila_capture_build51_*axis_ila_3.csv")
        status = decode_axis0(axis0)
        core = decode_core_bus(axis1)
        sd = decode_sd_init_debug_bus(axis2)
        ddr = decode_ddr_bus(axis3)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    failures = []
    warnings = []

    if status["core_seen"] is None:
        warnings.append("core_seen16 probe missing")
    else:
        if not ((status["core_seen"] >> 0) & 1):
            failures.append("tile reset rst_n_f did not release")
        if not ((status["core_seen"] >> 2) & 1):
            warnings.append("No transducer_l15_val request observed")
        if (status["core_seen"] >> 15) & 1:
            failures.append("L15 error observed")

    if status["sd_seen"] is None:
        warnings.append("sd_init_debug seen16 probe missing")
    else:
        if (status["sd_seen"] >> 1) & 1 and not ((status["sd_seen"] >> 2) & 1):
            warnings.append("sd_cd was only observed high; piton_sd_top reset may be held by card-detect")
        if not ((status["sd_seen"] >> 5) & 1):
            warnings.append("SD init_done was never observed")
        if not ((status["sd_seen"] >> 8) & 1):
            warnings.append("No SD controller Wishbone ack observed")
        if not ((status["sd_seen"] >> 11) & 1):
            warnings.append("No SD output clock toggle observed at chipset_clk sampler")

    if sd["flags16"] & (1 << 1) and sd["flags16"] & (1 << 2):
        warnings.append("current sd_cd=1 and sd_rst=1; card-detect is actively holding SD reset")
    if not (sd["flags16"] & (1 << 3)):
        warnings.append("current init_done=0, so sd_buf_noc2_ready is expected to remain low")

    if status["ddr_seen"] is None:
        warnings.append("ddr_seen16 probe missing")
    else:
        if (status["ddr_seen"] >> 7) & 1:
            failures.append("DDR write response error observed")
        if (status["ddr_seen"] >> 12) & 1:
            failures.append("DDR read response error observed")
        if not (((status["ddr_seen"] >> 6) & 1) or ((status["ddr_seen"] >> 11) & 1)):
            warnings.append("No completed DDR read or write response observed")

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
        return 1

    if warnings:
        print("WARN:")
        for warning in warnings:
            print(f"  - {warning}")

    print("PASS: Build 51 ILA decode completed without hard failures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
