#!/usr/bin/env python3
"""Decode Build 82 synchronized WT store request/return captures."""

import argparse
import glob
import os
import sys

import p3_decode_build80_ila_csv as build80


L15_ST_ACK = 0x4


def find_capture_set(directory):
    matches = sorted(
        glob.glob(
            os.path.join(
                directory,
                "ila_capture_build82_*_u_bd_openpiton_top_i_axis_ila_0.csv",
            )
        ),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 82 axis_ila_0 CSV in {directory}")
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
            raise FileNotFoundError(f"Build 82 LTX does not exist: {explicit}")
        return explicit
    path = os.path.abspath(
        os.path.join(directory, "..", "p3_top_build82_store_return_eco.ltx")
    )
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Build 82 LTX does not exist: {path}")
    return path


def vector_maps(layouts):
    axis0 = layouts["u_bd/openpiton_top_i/axis_ila_0"]
    result = {
        "trigger": {(port, bit): net for (port, bit), net in axis0.items() if port == 0},
        "pc": {
            (port - 1) * 16 + bit: net
            for (port, bit), net in axis0.items()
            if 1 <= port <= 4
        },
    }
    for index in range(1, 4):
        name = f"u_bd/openpiton_top_i/axis_ila_{index}"
        result[f"ila{index}"] = {
            bit: net for (port, bit), net in layouts[name].items() if port == 0
        }
    return result


def capture_trigger_samples(captures):
    """Return the CSV trigger index, not the sample count, for each capture."""
    return [capture[2] for capture in captures]


def decode_request(value):
    return {
        "trigger": value & 1,
        "tx_valid": (value >> 1) & 0x3,
        "req_status": (value >> 3) & 0x3,
        "req_read_ptr": (value >> 5) & 1,
        "req_write_ptr": (value >> 6) & 1,
        "req0_rtype": (value >> 7) & 0x3,
        "req0_tid": (value >> 9) & 1,
        "req1_rtype": (value >> 10) & 0x3,
        "req1_tid": (value >> 12) & 1,
        "stores_inflight": (value >> 13) & 0x3,
        "tx0_ptr": (value >> 15) & 0x7,
        "tx1_ptr": (value >> 18) & 0x7,
        "dirty_rd_en": (value >> 21) & 1,
        "miss_req": (value >> 22) & 1,
        "wbuffer_empty": (value >> 23) & 1,
        "no_st_pending": (value >> 24) & 1,
        "req0_paddr_low": (value >> 25) & 0xFFFF,
        "req1_paddr_low": (value >> 41) & 0xFFFF,
    }


def decode_adapter(value):
    return {
        "trigger": value & 1,
        "tx_valid": (value >> 1) & 0x3,
        "adapter_status": (value >> 3) & 1,
        "adapter_read_ptr": (value >> 4) & 1,
        "adapter_write_ptr": (value >> 5) & 1,
        "input_rtype": (value >> 6) & 0xF,
        "input_tid": (value >> 10) & 1,
        "front_rtype": (value >> 11) & 0xF,
        "mem0_rtype": (value >> 15) & 0xF,
        "mem0_tid": (value >> 19) & 1,
        "mem1_rtype": (value >> 20) & 0xF,
        "mem1_tid": (value >> 24) & 1,
        "stores_inflight": (value >> 25) & 0x3,
        "req_status": (value >> 27) & 0x3,
        "req_read_ptr": (value >> 29) & 1,
        "req_write_ptr": (value >> 30) & 1,
        "wbuffer_rtrn_status": (value >> 31) & 0x3,
        "wbuffer_rtrn_read_ptr": (value >> 33) & 1,
        "wbuffer_rtrn_write_ptr": (value >> 34) & 1,
        "wbuffer_mem0_tid": (value >> 35) & 1,
        "wbuffer_mem1_tid": (value >> 36) & 1,
        "wbuffer_input_tid": (value >> 37) & 1,
        "evict": (value >> 38) & 1,
        "checked": (value >> 39) & 0xFF,
    }


def decode_return(value):
    return {
        "trigger": value & 1,
        "tx_valid": (value >> 1) & 0x3,
        "stores_inflight": (value >> 3) & 0x3,
        "wbuffer_rtrn_status": (value >> 5) & 0x3,
        "wbuffer_rtrn_read_ptr": (value >> 7) & 1,
        "wbuffer_rtrn_write_ptr": (value >> 8) & 1,
        "wbuffer_mem0_tid": (value >> 9) & 1,
        "wbuffer_mem1_tid": (value >> 10) & 1,
        "wbuffer_input_tid": (value >> 11) & 1,
        "evict": (value >> 12) & 1,
        "wbuffer_empty": (value >> 13) & 1,
        "dirty_rd_en": (value >> 14) & 1,
        "miss_req": (value >> 15) & 1,
        "tx0_ptr": (value >> 16) & 0x7,
        "tx1_ptr": (value >> 19) & 0x7,
        "checked": (value >> 22) & 0xFF,
        "dirty": (value >> 30) & 0xFF,
        "entry2_txblock": (value >> 38) & 0xFF,
        "entry3_txblock": (value >> 46) & 0xFF,
        "adapter_status": (value >> 54) & 1,
        "adapter_read_ptr": (value >> 55) & 1,
        "adapter_write_ptr": (value >> 56) & 1,
        "req_status": (value >> 57) & 0x3,
        "req_read_ptr": (value >> 59) & 1,
        "req_write_ptr": (value >> 60) & 1,
    }


def changed_indices(states, field, first=1):
    return [
        index
        for index in range(max(1, first), len(states))
        if states[index][field] != states[index - 1][field]
    ]


def event_rtype(states, index, field):
    values = {states[index][field]}
    if index:
        values.add(states[index - 1][field])
    return values


def classify_capture(request, adapter, returned, trigger):
    req_pop = changed_indices(request, "req_read_ptr", trigger)
    adapter_push = changed_indices(adapter, "adapter_write_ptr", trigger)
    adapter_pop = changed_indices(adapter, "adapter_read_ptr", trigger)
    wbuffer_push = changed_indices(returned, "wbuffer_rtrn_write_ptr", trigger)
    evicts = [index for index in range(trigger, len(returned)) if returned[index]["evict"]]

    store_push = [
        index for index in adapter_push
        if L15_ST_ACK in event_rtype(adapter, index, "input_rtype")
    ]
    store_pop = [
        index for index in adapter_pop
        if L15_ST_ACK in event_rtype(adapter, index, "front_rtype")
    ]
    tx_stuck = (
        returned[-1]["tx_valid"] == 0x3
        and returned[-1]["wbuffer_empty"] == 0
    )

    events = {
        "req_pop": req_pop,
        "adapter_push": adapter_push,
        "adapter_store_push": store_push,
        "adapter_pop": adapter_pop,
        "adapter_store_pop": store_pop,
        "wbuffer_push": wbuffer_push,
        "evict": evicts,
    }
    if not tx_stuck:
        return "no_persistent_two_slot_stop", events
    if request[-1]["req_status"] and not req_pop:
        return "request_not_accepted_by_l15", events
    if not store_push:
        return "no_l15_store_ack", events
    if store_push and not store_pop:
        return "adapter_return_fifo_stuck", events
    if store_pop and not wbuffer_push:
        return "missunit_dropped_store_ack", events
    if wbuffer_push and not evicts:
        return "writebuffer_return_not_evicted", events
    if evicts and returned[-1]["tx_valid"] == 0x3:
        return "return_id_or_reallocation_mismatch", events
    return "unclassified", events


def format_events(name, indices, trigger):
    values = " ".join(f"{index - trigger:+d}" for index in indices[:16])
    suffix = " ..." if len(indices) > 16 else ""
    return f"  {name}: count={len(indices)} rel=[{values}{suffix}]"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 82 CSV files")
    parser.add_argument("--ltx", help="matching Build 82 LTX")
    parser.add_argument("--vmlinux", help="matching Linux ELF used to resolve PC")
    args = parser.parse_args()

    try:
        paths = find_capture_set(args.capture)
        ltx = find_ltx(args.capture, args.ltx)
        maps = vector_maps(build80.load_ltx_layout(ltx))
        captures = [build80.csvutil.read_capture(path) for path in paths]
        columns = [capture[0] for capture in captures]
        trigger_samples = capture_trigger_samples(captures)
        axis0_trigger = build80.reconstruct_from_net_map(
            columns[0], {0: next(iter(maps["trigger"].values()))}, 1
        )
        pc = build80.reconstruct_from_net_map(columns[0], maps["pc"], 64)
        raw_request = build80.reconstruct_from_net_map(columns[1], maps["ila1"], 64)
        raw_adapter = build80.reconstruct_from_net_map(columns[2], maps["ila2"], 64)
        raw_return = build80.reconstruct_from_net_map(columns[3], maps["ila3"], 64)
        trigger = build80.validate_synchronized_capture(
            [
                axis0_trigger,
                [value & 1 for value in raw_request],
                [value & 1 for value in raw_adapter],
                [value & 1 for value in raw_return],
            ],
            trigger_samples,
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    request = [decode_request(value) for value in raw_request]
    adapter = [decode_adapter(value) for value in raw_adapter]
    returned = [decode_return(value) for value in raw_return]
    if any(
        request[index]["trigger"] != adapter[index]["trigger"]
        or request[index]["trigger"] != returned[index]["trigger"]
        for index in range(len(request))
    ):
        print("ERROR: duplicated Build 82 triggers disagree", file=sys.stderr)
        return 1

    outcome, events = classify_capture(request, adapter, returned, trigger)
    print("Build 82 synchronized WT store-return capture:")
    for path in paths:
        print(f"  {path}")
    print(f"  trigger sample={trigger} pc=0x{pc[trigger]:016x}")
    print(
        "  trigger state: tx_valid=0x%x req_status=%d stores_inflight=%d "
        "req_ptr(r/w)=%d/%d"
        % (
            request[trigger]["tx_valid"], request[trigger]["req_status"],
            request[trigger]["stores_inflight"],
            request[trigger]["req_read_ptr"], request[trigger]["req_write_ptr"],
        )
    )
    print(
        "  request entries: rtype/tid/paddr_low="
        "%d/%d/0x%04x %d/%d/0x%04x"
        % (
            request[trigger]["req0_rtype"], request[trigger]["req0_tid"],
            request[trigger]["req0_paddr_low"], request[trigger]["req1_rtype"],
            request[trigger]["req1_tid"], request[trigger]["req1_paddr_low"],
        )
    )
    for name, indices in events.items():
        print(format_events(name, indices, trigger))
    print(
        "  final state: tx_valid=0x%x inflight=%d req_status=%d "
        "adapter_status=%d wbuffer_return_status=%d evict=%d"
        % (
            returned[-1]["tx_valid"], returned[-1]["stores_inflight"],
            returned[-1]["req_status"], returned[-1]["adapter_status"],
            returned[-1]["wbuffer_rtrn_status"], returned[-1]["evict"],
        )
    )
    print(
        "  final write buffer: empty=%d dirty=0x%02x txblock2/3=%02x/%02x "
        "tx_ptrs=%d,%d"
        % (
            returned[-1]["wbuffer_empty"], returned[-1]["dirty"],
            returned[-1]["entry2_txblock"], returned[-1]["entry3_txblock"],
            returned[-1]["tx0_ptr"], returned[-1]["tx1_ptr"],
        )
    )

    linked_pc = build80.linux_linked_address(pc[trigger])
    if args.vmlinux:
        for text in build80.csvutil.resolve_pc(linked_pc, args.vmlinux):
            print(text)

    messages = {
        "request_not_accepted_by_l15":
            "FAIL EDGE: D-cache store remains queued because L1.5 never accepts it",
        "no_l15_store_ack":
            "FAIL EDGE: L1.5 accepted the store request but no L15_ST_ACK returns",
        "adapter_return_fifo_stuck":
            "FAIL EDGE: L15_ST_ACK enters the adapter return FIFO but is not popped",
        "missunit_dropped_store_ack":
            "FAIL EDGE: adapter emits L15_ST_ACK but missunit does not push the write-buffer return ID",
        "writebuffer_return_not_evicted":
            "FAIL EDGE: return ID reaches the write buffer but does not produce evict",
        "return_id_or_reallocation_mismatch":
            "FAIL EDGE: evict occurs but both transaction slots remain occupied",
        "no_persistent_two_slot_stop":
            "INCONCLUSIVE: this run does not end in the persistent two-slot stop",
        "unclassified": "INCONCLUSIVE: captured state needs manual review",
    }
    print(messages[outcome])
    return 2 if outcome.startswith("no_") or outcome == "unclassified" else 0


if __name__ == "__main__":
    raise SystemExit(main())
