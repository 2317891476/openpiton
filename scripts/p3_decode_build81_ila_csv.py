#!/usr/bin/env python3
"""Decode Build 81 WT D-cache write-buffer final-state snapshots."""

import argparse
import glob
import os
import sys
from collections import Counter

import p3_decode_build80_ila_csv as build80


def find_snapshot_set(directory):
    matches = sorted(
        glob.glob(
            os.path.join(
                directory,
                "ila_snapshot_build81_*_u_bd_openpiton_top_i_axis_ila_0.csv",
            )
        ),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 81 axis_ila_0 CSV in {directory}")
    result = [matches[-1]]
    for index in range(1, 4):
        path = result[0].replace("_axis_ila_0.csv", f"_axis_ila_{index}.csv")
        if not os.path.isfile(path):
            raise FileNotFoundError(f"matching axis_ila_{index} CSV is missing: {path}")
        result.append(path)
    return result


def find_ltx(directory, explicit=None):
    if explicit:
        if not os.path.isfile(explicit):
            raise FileNotFoundError(f"Build 81 LTX does not exist: {explicit}")
        return explicit
    path = os.path.abspath(
        os.path.join(directory, "..", "p3_top_build81_wbuffer_eco.ltx")
    )
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Build 81 LTX does not exist: {path}")
    return path


def vector_maps(layouts):
    axis0 = layouts["u_bd/openpiton_top_i/axis_ila_0"]
    result = {
        "pc": {
            (port - 1) * 16 + bit: net
            for (port, bit), net in axis0.items()
            if 1 <= port <= 4
        }
    }
    for index in range(1, 4):
        name = f"u_bd/openpiton_top_i/axis_ila_{index}"
        result[f"ila{index}"] = {
            bit: net for (port, bit), net in layouts[name].items() if port == 0
        }
    return result


def decode_control(value):
    return {
        "commit_valid": value & 1,
        "commit_ack": (value >> 1) & 1,
        "fu": (value >> 2) & 0xF,
        "op": (value >> 6) & 0xFF,
        "no_st_pending": (value >> 14) & 1,
        "wbuffer_empty": (value >> 15) & 1,
        "checked": (value >> 16) & 0xFF,
        "tx_valid": (value >> 24) & 0x3,
        "tx0_ptr": (value >> 26) & 0x7,
        "tx1_ptr": (value >> 29) & 0x7,
        "tx0_be": (value >> 32) & 0xFF,
        "tx1_be": (value >> 40) & 0xFF,
        "miss_req": (value >> 48) & 1,
        "dirty_rd_en": (value >> 49) & 1,
        "check_en_q": (value >> 50) & 1,
        "check_en_q1": (value >> 51) & 1,
        "evict": (value >> 52) & 1,
        "checked_duplicate": (value >> 53) & 0x7F,
        "load_miss_req": (value >> 60) & 1,
        "dirty_ptr": (value >> 61) & 0x7,
    }


def entry_masks(value):
    return [(value >> (entry * 8)) & 0xFF for entry in range(8)]


def stable_value(series, name):
    value, count = Counter(series).most_common(1)[0]
    fraction = count / len(series)
    if fraction < 0.90:
        raise ValueError(f"{name} is stable for only {count}/{len(series)} samples")
    return value, count


def classify(control, dirty, txblock):
    blocked_fence = (
        control["commit_valid"] == 1
        and control["commit_ack"] == 0
        and control["fu"] == 0x6
        and control["op"] == 0x1C
        and control["no_st_pending"] == 1
        and control["wbuffer_empty"] == 0
    )
    if any(txblock) and control["tx_valid"] and not control["evict"]:
        return "fence_inflight_not_evicted" if blocked_fence else "inflight_not_evicted"
    if blocked_fence and any(dirty) and control["miss_req"] and not control["dirty_rd_en"]:
        return "miss_not_accepted"
    if blocked_fence:
        return "blocked_fence_other"
    return "not_blocked_fence"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 81 snapshots")
    parser.add_argument("--ltx", help="matching Build 81 LTX")
    parser.add_argument("--vmlinux", help="matching Linux ELF used to resolve PC")
    args = parser.parse_args()

    try:
        paths = find_snapshot_set(args.capture)
        ltx = find_ltx(args.capture, args.ltx)
        maps = vector_maps(build80.load_ltx_layout(ltx))
        captures = [build80.csvutil.read_capture(path) for path in paths]
        columns = [capture[0] for capture in captures]
        pc = build80.reconstruct_from_net_map(columns[0], maps["pc"], 64)
        dirty = build80.reconstruct_from_net_map(columns[1], maps["ila1"], 64)
        txblock = build80.reconstruct_from_net_map(columns[2], maps["ila2"], 64)
        control = build80.reconstruct_from_net_map(columns[3], maps["ila3"], 64)
        pc_value, pc_count = stable_value(pc, "commit PC")
        dirty_value, dirty_count = stable_value(dirty, "dirty-byte state")
        txblock_value, txblock_count = stable_value(txblock, "txblock-byte state")
        control_value, control_count = stable_value(control, "control state")
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    state = decode_control(control_value)
    dirty_masks = entry_masks(dirty_value)
    txblock_masks = entry_masks(txblock_value)
    if state["checked_duplicate"] != (state["checked"] & 0x7F):
        print("ERROR: duplicated checked bits disagree with the primary field", file=sys.stderr)
        return 1
    print("Build 81 persistent WT D-cache state:")
    for path in paths:
        print(f"  {path}")
    print(
        f"  stable samples pc/dirty/txblock/control="
        f"{pc_count}/{dirty_count}/{txblock_count}/{control_count}"
    )
    print(
        "  commit pc=0x%016x valid/ack=%d/%d fu=%s op=%s"
        % (
            pc_value,
            state["commit_valid"],
            state["commit_ack"],
            build80.FU_NAMES.get(state["fu"], hex(state["fu"])),
            build80.OP_NAMES.get(state["op"], hex(state["op"])),
        )
    )
    print(
        "  drain gate: store_queue_empty=%d wbuffer_empty=%d checked=0x%02x"
        % (state["no_st_pending"], state["wbuffer_empty"], state["checked"])
    )
    print("  entry dirty masks:   " + " ".join(f"{mask:02x}" for mask in dirty_masks))
    print("  entry txblock masks: " + " ".join(f"{mask:02x}" for mask in txblock_masks))
    free_slots = 2 - state["tx_valid"].bit_count()
    print(
        "  tx slots: valid=0x%x free=%d ptrs=%d,%d be=%02x,%02x dirty_ptr=%d"
        % (
            state["tx_valid"], free_slots, state["tx0_ptr"], state["tx1_ptr"],
            state["tx0_be"], state["tx1_be"], state["dirty_ptr"],
        )
    )
    print(
        "  progress: miss_req=%d allocate=%d check_q/q1=%d/%d evict=%d "
        "load_miss_req=%d"
        % (
            state["miss_req"], state["dirty_rd_en"], state["check_en_q"],
            state["check_en_q1"], state["evict"], state["load_miss_req"],
        )
    )

    linked_pc = build80.linux_linked_address(pc_value)
    if args.vmlinux:
        for text in build80.csvutil.resolve_pc(linked_pc, args.vmlinux):
            print(text)

    outcome = classify(state, dirty_masks, txblock_masks)
    if outcome == "miss_not_accepted":
        print("PASS: FENCE is blocked because a dirty write-buffer request is not accepted")
        return 0
    if outcome == "fence_inflight_not_evicted":
        print("PASS: FENCE is blocked by an in-flight write-buffer transaction that is not evicted")
        return 0
    if outcome == "inflight_not_evicted":
        print("PASS: write-buffer transactions remain in flight and are not evicted")
        print("NOTE: the current commit head is not a valid blocked FENCE")
        return 0
    if outcome == "blocked_fence_other":
        print("PASS: FENCE is blocked by a non-empty write buffer; captured substate needs review")
        return 0
    print("INCONCLUSIVE: snapshot does not reproduce the persistent Build 80 FENCE stop")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
