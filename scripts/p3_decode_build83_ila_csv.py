#!/usr/bin/env python3
"""Decode synchronized Build 83 orphan return-ID captures."""

import argparse
import glob
import os
import sys

import p3_decode_build80_ila_csv as build80


L15_ST_ACK = 0x4


def find_capture_set(directory, orphan_case=None):
    token = orphan_case or "*"
    matches = sorted(
        glob.glob(
            os.path.join(
                directory,
                f"ila_capture_build83_{token}_*_u_bd_openpiton_top_i_axis_ila_0.csv",
            )
        ),
        key=os.path.getmtime,
    )
    if not matches:
        raise FileNotFoundError(f"no Build 83 axis_ila_0 CSV in {directory}")
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
            raise FileNotFoundError(f"Build 83 LTX does not exist: {explicit}")
        return explicit
    path = os.path.abspath(
        os.path.join(directory, "..", "p3_top_build83_orphan_return_eco.ltx")
    )
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Build 83 LTX does not exist: {path}")
    return path


def vector_maps(layouts):
    axis0 = layouts["u_bd/openpiton_top_i/axis_ila_0"]
    ila0 = {0: axis0[(0, 0)]}
    for port in range(1, 5):
        for bit in range(16):
            ila0[1 + (port - 1) * 16 + bit] = axis0[(port, bit)]
    result = {"ila0": ila0}
    for index in range(1, 4):
        name = f"u_bd/openpiton_top_i/axis_ila_{index}"
        result[f"ila{index}"] = {
            bit: net for (port, bit), net in layouts[name].items() if port == 0
        }
    return result


def decode_common(value):
    return {
        "return_status": value & 0x3,
        "return_read_ptr": (value >> 2) & 1,
        "return_mem0_tid": (value >> 3) & 1,
        "return_mem1_tid": (value >> 4) & 1,
        "tx_valid": (value >> 5) & 0x3,
    }


def head_tid(state):
    return state[f"return_mem{state['return_read_ptr']}_tid"]


def is_orphan(state):
    if state["return_status"] == 0:
        return False
    return not (state["tx_valid"] & (1 << head_tid(state)))


def decode_ila0(value):
    state = decode_common(value)
    state.update({
        "req_status": (value >> 7) & 0x3,
        "req_read_ptr": (value >> 9) & 1,
        "req_write_ptr": (value >> 10) & 1,
        "req0_rtype": (value >> 11) & 0x3,
        "req0_tid": (value >> 13) & 1,
        "req0_paddr_low": (value >> 14) & 0x3FF,
        "req1_rtype": (value >> 24) & 0x3,
        "req1_tid": (value >> 26) & 1,
        "req1_paddr_low": (value >> 27) & 0x3FF,
        "stores_inflight": (value >> 37) & 0x3,
        "dirty_rd_en": (value >> 39) & 1,
        "tx0_ptr": (value >> 40) & 0x7,
        "tx1_ptr": (value >> 43) & 0x7,
        "tx0_be": (value >> 46) & 0xFF,
        "tx1_be": (value >> 54) & 0xFF,
        "miss_req": (value >> 62) & 1,
        "wbuffer_empty": (value >> 63) & 1,
        "no_st_pending": (value >> 64) & 1,
    })
    return state


def decode_adapter_prefix(value):
    state = decode_common(value)
    state.update({
        "adapter_status": (value >> 7) & 1,
        "adapter_read_ptr": (value >> 8) & 1,
        "adapter_write_ptr": (value >> 9) & 1,
        "adapter_input_rtype": (value >> 10) & 0xF,
        "adapter_input_tid": (value >> 14) & 1,
        "adapter_front_rtype": (value >> 15) & 0xF,
        "adapter_mem0_rtype": (value >> 19) & 0xF,
        "adapter_mem0_tid": (value >> 23) & 1,
        "adapter_mem1_rtype": (value >> 24) & 0xF,
        "adapter_mem1_tid": (value >> 28) & 1,
        "stores_inflight": (value >> 29) & 0x3,
        "wreturn_status": (value >> 31) & 0x3,
        "wreturn_read_ptr": (value >> 33) & 1,
        "wreturn_write_ptr": (value >> 34) & 1,
        "wreturn_mem0_tid": (value >> 35) & 1,
        "wreturn_mem1_tid": (value >> 36) & 1,
        "wreturn_input_tid": (value >> 37) & 1,
        "evict": (value >> 38) & 1,
        "tx0_ptr": (value >> 39) & 0x7,
        "tx1_ptr": (value >> 42) & 0x7,
    })
    return state


def decode_ila1(value):
    state = decode_adapter_prefix(value)
    state.update({
        "checked": (value >> 45) & 0xFF,
        "req_status": (value >> 53) & 0x3,
        "req_read_ptr": (value >> 55) & 1,
        "req_write_ptr": (value >> 56) & 1,
        "req0_rtype": (value >> 57) & 0x3,
        "req0_tid": (value >> 59) & 1,
        "req1_rtype": (value >> 60) & 0x3,
        "req1_tid": (value >> 62) & 1,
        "miss_req": (value >> 63) & 1,
    })
    return state


def decode_ila2(value):
    state = decode_adapter_prefix(value)
    state.update({
        "tx0_be": (value >> 45) & 0xFF,
        "tx1_be": (value >> 53) & 0xFF,
        "dirty_rd_en": (value >> 61) & 1,
        "miss_req": (value >> 62) & 1,
        "wbuffer_empty": (value >> 63) & 1,
    })
    return state


def decode_ila3(value):
    state = decode_common(value)
    state.update({
        "wreturn_status": (value >> 7) & 0x3,
        "wreturn_read_ptr": (value >> 9) & 1,
        "wreturn_write_ptr": (value >> 10) & 1,
        "wreturn_mem0_tid": (value >> 11) & 1,
        "wreturn_mem1_tid": (value >> 12) & 1,
        "wreturn_input_tid": (value >> 13) & 1,
        "evict": (value >> 14) & 1,
        "tx0_ptr": (value >> 15) & 0x7,
        "tx1_ptr": (value >> 18) & 0x7,
        "tx0_be": (value >> 21) & 0xFF,
        "tx1_be": (value >> 29) & 0xFF,
        "checked": (value >> 37) & 0xFF,
        "dirty": (value >> 45) & 0xFF,
        "txblock_byte0": (value >> 53) & 0xFF,
        "dirty_rd_en": (value >> 61) & 1,
        "miss_req": (value >> 62) & 1,
        "wbuffer_empty": (value >> 63) & 1,
    })
    return state


def changed_indices(states, field, first=1):
    return [
        index for index in range(max(1, first), len(states))
        if states[index][field] != states[index - 1][field]
    ]


def rising_indices(states, field, first=1):
    return [
        index for index in range(max(1, first), len(states))
        if not states[index - 1][field] and states[index][field]
    ]


def classify_orphan(states, adapter, trigger):
    previous = states[trigger - 1]
    current = states[trigger]
    tid = head_tid(current)
    return_push = (
        current["wreturn_write_ptr"] != previous["wreturn_write_ptr"]
        or current["wreturn_status"] > previous["wreturn_status"]
    )
    adapter_push = adapter[trigger]["adapter_write_ptr"] != adapter[trigger - 1]["adapter_write_ptr"]
    source_store_ack = (
        adapter_push
        and adapter[trigger]["adapter_input_rtype"] == L15_ST_ACK
        and adapter[trigger]["adapter_input_tid"] == tid
    )
    previous_valid = bool(previous["tx_valid"] & (1 << tid))
    if return_push and not previous_valid:
        if source_store_ack:
            return "late_or_duplicate_store_ack_for_inactive_slot"
        return "return_id_pushed_for_inactive_slot"
    if previous["return_status"] == 2 and current["return_status"] == 1:
        return "queued_orphan_revealed_after_prior_return_pop"
    if previous_valid and not (current["tx_valid"] & (1 << tid)):
        return "same_cycle_slot_clear_and_orphan_visibility"
    return "orphan_transition_unclassified"


def format_events(name, indices, trigger):
    values = " ".join(f"{index - trigger:+d}" for index in indices[:24])
    suffix = " ..." if len(indices) > 24 else ""
    return f"  {name}: count={len(indices)} rel=[{values}{suffix}]"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 83 CSV files")
    parser.add_argument("--case", help="specific orphan case, for example rp0_tid0")
    parser.add_argument("--ltx", help="matching Build 83 LTX")
    args = parser.parse_args()

    try:
        paths = find_capture_set(args.capture, args.case)
        ltx = find_ltx(args.capture, args.ltx)
        maps = vector_maps(build80.load_ltx_layout(ltx))
        captures = [build80.csvutil.read_capture(path) for path in paths]
        columns = [capture[0] for capture in captures]
        counts = [capture[1] for capture in captures]
        trigger_samples = [capture[2] for capture in captures]
        raw = [
            build80.reconstruct_from_net_map(columns[index], maps[f"ila{index}"],
                                             65 if index == 0 else 64)
            for index in range(4)
        ]
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if len(set(counts)) != 1 or len(set(trigger_samples)) != 1:
        print(f"ERROR: sample/trigger mismatch counts={counts} triggers={trigger_samples}",
              file=sys.stderr)
        return 1
    request = [decode_ila0(value) for value in raw[0]]
    adapter = [decode_ila1(value) for value in raw[1]]
    response = [decode_ila2(value) for value in raw[2]]
    wbuffer = [decode_ila3(value) for value in raw[3]]
    common = [[decode_common(value) for value in series] for series in raw]
    if any(series != common[0] for series in common[1:]):
        print("ERROR: duplicated Build 83 common state is not synchronized", file=sys.stderr)
        return 1
    trigger = trigger_samples[0]
    if trigger == 0 or not is_orphan(common[0][trigger]) or is_orphan(common[0][trigger - 1]):
        print(f"ERROR: trigger sample {trigger} is not the first orphan transition",
              file=sys.stderr)
        return 1

    outcome = classify_orphan(response, adapter, trigger)
    state = common[0][trigger]
    tid = head_tid(state)
    events = {
        "request_fifo_pop": changed_indices(request, "req_read_ptr"),
        "adapter_push": changed_indices(adapter, "adapter_write_ptr"),
        "adapter_pop": changed_indices(adapter, "adapter_read_ptr"),
        "stores_inflight_change": changed_indices(response, "stores_inflight"),
        "return_fifo_push": changed_indices(response, "wreturn_write_ptr"),
        "return_fifo_pop": changed_indices(response, "wreturn_read_ptr"),
        "tx_valid_change": changed_indices(response, "tx_valid"),
        "dirty_allocate": rising_indices(response, "dirty_rd_en"),
        "evict": [index for index, item in enumerate(response) if item["evict"]],
    }

    print("Build 83 synchronized orphan return-ID capture:")
    for path in paths:
        print(f"  {path}")
    print(
        "  trigger sample=%d return_status=%d readptr=%d head_tid=%d tx_valid=0x%x"
        % (trigger, state["return_status"], state["return_read_ptr"], tid,
           state["tx_valid"])
    )
    before = common[0][trigger - 1]
    print(
        "  previous: return_status=%d readptr=%d head_tid=%d tx_valid=0x%x"
        % (before["return_status"], before["return_read_ptr"], head_tid(before),
           before["tx_valid"])
    )
    print(
        "  adapter at trigger: status=%d ptr(r/w)=%d/%d input_rtype/tid=%d/%d "
        "front_rtype=%d stores_inflight=%d"
        % (adapter[trigger]["adapter_status"], adapter[trigger]["adapter_read_ptr"],
           adapter[trigger]["adapter_write_ptr"],
           adapter[trigger]["adapter_input_rtype"],
           adapter[trigger]["adapter_input_tid"],
           adapter[trigger]["adapter_front_rtype"],
           adapter[trigger]["stores_inflight"])
    )
    print(
        "  write buffer at trigger: return_ptr(r/w)=%d/%d input_tid=%d evict=%d "
        "tx_ptrs=%d,%d checked=0x%02x dirty=0x%02x txblock0=0x%02x"
        % (wbuffer[trigger]["wreturn_read_ptr"],
           wbuffer[trigger]["wreturn_write_ptr"],
           wbuffer[trigger]["wreturn_input_tid"], wbuffer[trigger]["evict"],
           wbuffer[trigger]["tx0_ptr"], wbuffer[trigger]["tx1_ptr"],
           wbuffer[trigger]["checked"], wbuffer[trigger]["dirty"],
           wbuffer[trigger]["txblock_byte0"])
    )
    for name, indices in events.items():
        nearby = [index for index in indices if trigger - 128 <= index <= trigger + 32]
        print(format_events(name, nearby, trigger))

    messages = {
        "late_or_duplicate_store_ack_for_inactive_slot":
            "FAIL EDGE: adapter delivered a store ACK for a transaction slot that was already inactive",
        "return_id_pushed_for_inactive_slot":
            "FAIL EDGE: write-buffer return FIFO accepted an ID for an already inactive slot",
        "queued_orphan_revealed_after_prior_return_pop":
            "FAIL EDGE: popping a valid return exposed a second queued ID with no active slot",
        "same_cycle_slot_clear_and_orphan_visibility":
            "FAIL EDGE: transaction-slot clear and orphan return visibility occur in the same cycle",
        "orphan_transition_unclassified":
            "INCONCLUSIVE: orphan transition captured but source timing needs manual review",
    }
    print(messages[outcome])
    return 2 if outcome == "orphan_transition_unclassified" else 0


if __name__ == "__main__":
    raise SystemExit(main())
