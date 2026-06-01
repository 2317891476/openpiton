#!/usr/bin/env python3
"""Decode Build 56 standalone SD dual-probe ILA CSV captures."""

import argparse
import csv
import glob
import os
import sys


STATE_NAMES = {
    0x00: "IDLE",
    0x01: "POWER_WAIT",
    0x02: "IDLE_CLOCKS",
    0x03: "CMD_LOAD",
    0x04: "CMD_LOW",
    0x05: "CMD_HIGH",
    0x10: "SPI_RESP_LOW",
    0x11: "SPI_RESP_HIGH",
    0x20: "NATIVE_WAIT_L",
    0x21: "NATIVE_WAIT_H",
    0xE0: "RECORD",
    0xE1: "ALL_DONE",
    0xF0: "PASS",
    0xF1: "FAIL",
}

COMBO_NAMES = ["ref_spi", "ref_native", "phc3_spi", "phc3_native"]


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
        values[name] = parse_hex(col[-1])
        uniques[name] = sorted(set(col))
    return values, uniques, len(samples)


def find_signal(values, needle):
    matches = [name for name in values if needle in name]
    if not matches:
        raise KeyError(f"missing signal containing {needle!r}; available={list(values)}")
    return matches[0], values[matches[0]]


def decode_one(path):
    values, uniques, samples = read_csv(path)
    status_name, status = find_signal(values, "p3_sd_status_i")
    bus0_name, bus0 = find_signal(values, "p3_sd_bus0_i")
    bus1_name, bus1 = find_signal(values, "p3_sd_bus1_i")
    summary_name, summary = find_signal(values, "p3_sd_summary_i")

    state = status & 0xFF
    busy = (status >> 8) & 1
    done = (status >> 9) & 1
    passed = (status >> 10) & 1
    failed = (status >> 11) & 1
    pin_sel = (status >> 12) & 1
    proto_sel = (status >> 13) & 1
    spi_seen = (status >> 14) & 1
    native_seen = (status >> 15) & 1
    timeout = (status >> 16) & 1
    sd_cd = (status >> 17) & 1
    drive_sd = (status >> 18) & 1
    all_done = (status >> 19) & 1
    fail_code = (status >> 24) & 0xFF

    response_timeout = bus0 & 0xFFFF
    clk_toggle_count = (bus0 >> 16) & 0xFFFF
    dat_i = (bus0 >> 32) & 0xF
    dat_o = (bus0 >> 36) & 0xF
    dat_oe = (bus0 >> 40) & 0xF
    cmd_i = (bus0 >> 44) & 1
    cmd_o = (bus0 >> 45) & 1
    cmd_oe = (bus0 >> 46) & 1
    clk_o = (bus0 >> 47) & 1
    response_byte = (bus0 >> 48) & 0xFF
    marker = (bus0 >> 56) & 0xFF

    response_shift = bus1 & ((1 << 40) - 1)
    response_bit_count = (bus1 >> 40) & 0x7
    bit_count = (bus1 >> 48) & 0x3F
    command_index = (bus1 >> 56) & 0xFF

    combo_fail_code = summary & 0xFFFFFFFF
    combo_resp_seen = (summary >> 32) & 0xF
    combo_timeout = (summary >> 36) & 0xF
    combo_fail = (summary >> 40) & 0xF
    combo_pass = (summary >> 44) & 0xF
    combo_done = (summary >> 48) & 0xF
    summary_all_done = (summary >> 55) & 1
    summary_marker = (summary >> 56) & 0xFF

    combo = os.path.basename(path).replace("ila_capture_build56_", "").replace(".csv", "")
    print(f"{combo}: {path}")
    print(f"  samples={samples}")
    print(f"  {status_name}=0x{status:08x}")
    print(
        "  state=0x%02x %s busy=%d done=%d pass=%d fail=%d fail_code=0x%02x"
        % (state, STATE_NAMES.get(state, "UNKNOWN"), busy, done, passed, failed, fail_code)
    )
    print(
        "  pin=%s proto=%s sd_cd=%d drive_sd=%d all_done=%d timeout=%d"
        % (
            "p3_io_phc3" if pin_sel else "reference",
            "native" if proto_sel else "spi",
            sd_cd,
            drive_sd,
            all_done,
            timeout,
        )
    )
    print(
        "  seen: spi_miso_low=%d native_cmd_resp=%d response_byte=0x%02x response_shift=0x%010x"
        % (spi_seen, native_seen, response_byte, response_shift)
    )
    print(
        "  io: clk=%d cmd_i/o/oe=%d/%d/%d dat_i/o/oe=0x%x/0x%x/0x%x"
        % (clk_o, cmd_i, cmd_o, cmd_oe, dat_i, dat_o, dat_oe)
    )
    print(
        "  counters: clk_toggle=%d response_timeout=%d command_index=%d bit_count=%d resp_bits=%d marker=0x%02x"
        % (clk_toggle_count, response_timeout, command_index, bit_count, response_bit_count, marker)
    )
    print(f"  {summary_name}=0x{summary:016x} marker=0x{summary_marker:02x} all_done={summary_all_done}")
    for idx, name in enumerate(COMBO_NAMES):
        code = (combo_fail_code >> (idx * 8)) & 0xFF
        print(
            "    %-12s done=%d pass=%d fail=%d timeout=%d resp_seen=%d fail_code=0x%02x"
            % (
                name,
                (combo_done >> idx) & 1,
                (combo_pass >> idx) & 1,
                (combo_fail >> idx) & 1,
                (combo_timeout >> idx) & 1,
                (combo_resp_seen >> idx) & 1,
                code,
            )
        )

    if combo_pass:
        return "PASS"
    if all_done or combo_fail:
        return "FAIL"
    return "UNKNOWN"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debug_build_dir", help="huaprop3_build56_sd_dual_probe/debug_build")
    args = parser.parse_args()
    matches = sorted(glob.glob(os.path.join(args.debug_build_dir, "ila_capture_build56_*.csv")))
    if not matches:
        print("ERROR: no Build 56 ILA CSV files found", file=sys.stderr)
        return 1

    results = {}
    try:
        for path in matches:
            result = decode_one(path)
            results[os.path.basename(path)] = result
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print("Summary:")
    for name, result in results.items():
        print(f"  {name}: {result}")

    any_pass = any(result == "PASS" for result in results.values())
    return 0 if any_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
