#!/usr/bin/env python3
"""Decode Build 78 store-drain and core-to-L1.5 ECO snapshots."""

import argparse
import glob
import os
import sys
from collections import Counter

import p3_decode_build76_ila_csv as build77


CORE_FLAG_NAMES = [
    "clk_en",
    "spc_grst_l",
    "rst_n_f",
    "l15_transducer_error",
    "l15_transducer_ack",
    "l15_transducer_val",
    "transducer_l15_req_ack",
    "transducer_l15_val",
]

ARIANE_DEBUG_HI_NAMES = [
    "external_irq_any",
    "ipi_i",
    "time_irq_i",
    "debug_req_i",
    "reset_l",
    "spc_grst_l",
    "rst_n",
    "wake_up_done",
]


def decode_core_bus(value):
    return {
        "last_l15_addr": (value >> 24) & ((1 << 40) - 1),
        "last_l15_rqtype": (value >> 19) & 0x1F,
        "last_l15_size": (value >> 16) & 0x7,
        "ariane_debug_hi": (value >> 8) & 0xFF,
        "flags": value & 0xFF,
    }


def decode_store_diag(value):
    return {
        "no_st_pending_ex": value & 1,
        "dcache_wbuffer_empty": (value >> 1) & 1,
        "commit_status_count": (value >> 2) & 0x7,
        "commit_read_pointer": (value >> 5) & 0x3,
        "wbuffer_valid": (value >> 7) & 0xFF,
        "wbuffer_dirty": (value >> 15) & 0xFF,
        "tx_valid": (value >> 23) & 0x3,
        "tx0_pointer": (value >> 25) & 0x7,
        "tx1_pointer": (value >> 28) & 0x7,
        "dirty_pointer": (value >> 31) & 0x7,
        "evict": (value >> 34) & 1,
        "filler": (value >> 35) & 1,
    }


def set_bits(value, width):
    return [bit for bit in range(width) if (value >> bit) & 1]


def find_capture_pair(directory):
    core_matches = sorted(
        glob.glob(os.path.join(directory, "ila_snapshot_build78_*_axis_ila_1.csv"))
    )
    if not core_matches:
        raise FileNotFoundError(f"no Build 78 axis_ila_1 CSV in {directory}")
    core_path = core_matches[-1]
    status_path = core_path.replace("_axis_ila_1.csv", "_axis_ila_2.csv")
    if not os.path.isfile(status_path):
        raise FileNotFoundError(f"matching axis_ila_2 CSV is missing: {status_path}")
    return core_path, status_path


def common_summary(series):
    value, count = Counter(series).most_common(1)[0]
    return value, count, count / len(series)


def classify_outcome(core, commit, diag):
    live_request = (core["flags"] >> 7) & 1
    request_ack = (core["flags"] >> 6) & 1
    blocked_fence = (
        commit["valid"] == 1
        and commit["ack"] == 0
        and commit["fu"] == 0x6
        and commit["op"] == 0x1C
        and commit["stall_s1"] == 1
        and live_request == 1
        and request_ack == 0
    )
    drained_idle = (
        commit["valid"] == 0
        and commit["stall_s1"] == 0
        and commit["stall_s2"] == 0
        and commit["stall_s3"] == 0
        and live_request == 0
        and diag["no_st_pending_ex"] == 1
        and diag["dcache_wbuffer_empty"] == 1
        and diag["commit_status_count"] == 0
        and diag["wbuffer_valid"] == 0
        and diag["wbuffer_dirty"] == 0
        and diag["tx_valid"] == 0
    )
    if blocked_fence:
        return "blocked_fence"
    if drained_idle:
        return "drained_idle"
    return "other"


def one_vector_probe(columns, token):
    matches = [series for name, series in columns.items() if token in name]
    if len(matches) != 1:
        raise ValueError(f"expected one {token} vector probe, found {len(matches)}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 78 snapshot CSVs")
    args = parser.parse_args()

    try:
        core_path, status_path = find_capture_pair(args.capture)
        core_columns, core_count, core_trigger = build77.read_capture(core_path)
        status_columns, status_count, status_trigger = build77.read_capture(status_path)
        core_series = one_vector_probe(core_columns, "p3_dbg_core_bus64_i_1")
        commit_series = build77.reconstruct_split_probe(
            status_columns,
            "axis_ila_2_probe0",
            28,
            aliases={0: "p3_build77_commit_valid"},
        )
        diag_series = build77.reconstruct_split_probe(
            status_columns,
            "p3_build78_diag",
            36,
            aliases={35: "p3_dbg_uart_bus64_i_1"},
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    core_raw = core_series[core_trigger]
    commit_raw = commit_series[status_trigger]
    diag_raw = diag_series[status_trigger]
    core = decode_core_bus(core_raw)
    commit = build77.decode_status(commit_raw)
    diag = decode_store_diag(diag_raw)
    core_common, core_common_count, core_fraction = common_summary(core_series)
    commit_common, commit_common_count, commit_fraction = common_summary(commit_series)
    diag_common, diag_common_count, diag_fraction = common_summary(diag_series)

    print(f"Build 78 core/L1.5 capture: {core_path}")
    print(f"Build 78 store-path capture: {status_path}")
    print(
        "  core samples=%d trigger=%d raw=0x%016x stable=%d/%d (%.1f%%)"
        % (core_count, core_trigger, core_raw, core_common_count, core_count,
           core_fraction * 100.0)
    )
    print(
        "  sticky last L1.5 request: address=0x%010x rqtype=0x%02x size=0x%x"
        % (core["last_l15_addr"], core["last_l15_rqtype"], core["last_l15_size"])
    )
    print(
        "  L1.5 flags=0x%02x set=%s"
        % (core["flags"], set_bits(core["flags"], 8))
    )
    for bit, name in enumerate(CORE_FLAG_NAMES):
        print(f"    bit{bit}: {name}={(core['flags'] >> bit) & 1}")
    print(
        "  Ariane wrapper debug=0x%02x set=%s"
        % (core["ariane_debug_hi"], set_bits(core["ariane_debug_hi"], 8))
    )
    for bit, name in enumerate(ARIANE_DEBUG_HI_NAMES):
        print(
            f"    bit{bit}: {name}={(core['ariane_debug_hi'] >> bit) & 1}"
        )
    print(
        "  commit raw=0x%07x stable=%d/%d (%.1f%%): "
        "valid=%d ack=%d fu=0x%x(%s) op=0x%02x(%s) stall_s1=%d"
        % (
            commit_raw,
            commit_common_count,
            status_count,
            commit_fraction * 100.0,
            commit["valid"],
            commit["ack"],
            commit["fu"],
            build77.FU_NAMES.get(commit["fu"], "UNKNOWN"),
            commit["op"],
            build77.OP_NAMES.get(commit["op"], "UNKNOWN"),
            commit["stall_s1"],
        )
    )
    print(
        "  store path raw=0x%09x stable=%d/%d (%.1f%%): "
        "no_st_pending_ex=%d dcache_wbuffer_empty=%d commit_count=%d "
        "commit_rptr=%d"
        % (
            diag_raw,
            diag_common_count,
            status_count,
            diag_fraction * 100.0,
            diag["no_st_pending_ex"],
            diag["dcache_wbuffer_empty"],
            diag["commit_status_count"],
            diag["commit_read_pointer"],
        )
    )
    print(
        "  WT write buffer: valid=0x%02x entries=%s dirty=0x%02x entries=%s "
        "tx_valid=0x%x tx_ptrs=%d,%d dirty_ptr=%d evict=%d"
        % (
            diag["wbuffer_valid"],
            set_bits(diag["wbuffer_valid"], 8),
            diag["wbuffer_dirty"],
            set_bits(diag["wbuffer_dirty"], 8),
            diag["tx_valid"],
            diag["tx0_pointer"],
            diag["tx1_pointer"],
            diag["dirty_pointer"],
            diag["evict"],
        )
    )

    failures = []
    if core_raw != core_common or core_fraction < 0.90:
        failures.append("core/L1.5 request state is not persistent")
    if commit_raw != commit_common or commit_fraction < 0.90:
        failures.append("commit state is not persistent")
    if diag_raw != diag_common or diag_fraction < 0.90:
        failures.append("store-path state is not persistent")
    if diag["no_st_pending_ex"] != (diag["commit_status_count"] == 0):
        failures.append("store queue empty flag disagrees with commit queue count")
    if failures:
        print("INCONCLUSIVE:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    outcome = classify_outcome(core, commit, diag)
    if outcome == "blocked_fence":
        layers = []
        if not diag["no_st_pending_ex"]:
            layers.append("CVA6 committed-store queue is non-empty")
        if not diag["dcache_wbuffer_empty"]:
            layers.append("WT D-cache write buffer is non-empty")
        print("PASS: blocked FENCE is waiting behind an unacknowledged L1.5 request")
        print(f"  persistent request address: 0x{core['last_l15_addr']:010x}")
        for layer in layers:
            print(f"  active layer: {layer}")
        print("  L1.5 S1 sub-blocker is unavailable in the retained Build 66 netlist")
        return 0
    if outcome == "drained_idle":
        timer_irq = (core["ariane_debug_hi"] >> 2) & 1
        print(
            "PASS: committed-store queue and WT write buffer are drained "
            "while the core has no commit head"
        )
        print("  Build 77's blocked FENCE is not the persistent stop in this run")
        print(f"  synchronized timer interrupt input: {timer_irq}")
        print("  next diagnostic boundary: WFI/halt and mip/mie interrupt wake state")
        return 0

    print("INCONCLUSIVE:")
    print("  - stable state is neither a blocked FENCE nor a fully drained idle core")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
