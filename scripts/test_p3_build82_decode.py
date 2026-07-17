#!/usr/bin/env python3
"""Focused tests for the Build 82 store-return decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build82_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build82", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def request_state(**updates):
    state = {
        "req_status": 0, "req_read_ptr": 0, "req_write_ptr": 0,
        "tx_valid": 3, "stores_inflight": 2,
    }
    state.update(updates)
    return state


def adapter_state(**updates):
    state = {
        "adapter_write_ptr": 0, "adapter_read_ptr": 0,
        "input_rtype": 0, "front_rtype": 0,
    }
    state.update(updates)
    return state


def return_state(**updates):
    state = {
        "wbuffer_rtrn_write_ptr": 0, "evict": 0,
        "tx_valid": 3, "wbuffer_empty": 0,
    }
    state.update(updates)
    return state


class Build82DecodeTests(unittest.TestCase):
    def test_decodes_request_layout(self):
        value = (
            1 | (3 << 1) | (2 << 3) | (1 << 5) | (1 << 7) |
            (1 << 9) | (2 << 10) | (3 << 13) | (4 << 15) | (5 << 18) |
            (0x1234 << 25) | (0xABCD << 41)
        )
        state = MODULE.decode_request(value)
        self.assertEqual(state["tx_valid"], 3)
        self.assertEqual(state["req_status"], 2)
        self.assertEqual((state["tx0_ptr"], state["tx1_ptr"]), (4, 5))
        self.assertEqual((state["req0_paddr_low"], state["req1_paddr_low"]),
                         (0x1234, 0xABCD))

    def test_request_not_accepted(self):
        req = [request_state(req_status=1) for _ in range(6)]
        adapter = [adapter_state() for _ in range(6)]
        returned = [return_state() for _ in range(6)]
        outcome, _ = MODULE.classify_capture(req, adapter, returned, 1)
        self.assertEqual(outcome, "request_not_accepted_by_l15")

    def test_no_l15_store_ack(self):
        req = [request_state() for _ in range(6)]
        req[2]["req_read_ptr"] = 1
        req[3]["req_read_ptr"] = 1
        req[4]["req_read_ptr"] = 1
        req[5]["req_read_ptr"] = 1
        adapter = [adapter_state() for _ in range(6)]
        returned = [return_state() for _ in range(6)]
        outcome, _ = MODULE.classify_capture(req, adapter, returned, 1)
        self.assertEqual(outcome, "no_l15_store_ack")

    def test_missunit_drops_store_ack(self):
        req = [request_state() for _ in range(6)]
        adapter = [adapter_state() for _ in range(6)]
        adapter[2].update(adapter_write_ptr=1, input_rtype=MODULE.L15_ST_ACK)
        adapter[3].update(adapter_write_ptr=1, adapter_read_ptr=1,
                          front_rtype=MODULE.L15_ST_ACK)
        adapter[4].update(adapter_write_ptr=1, adapter_read_ptr=1)
        adapter[5].update(adapter_write_ptr=1, adapter_read_ptr=1)
        returned = [return_state() for _ in range(6)]
        outcome, _ = MODULE.classify_capture(req, adapter, returned, 1)
        self.assertEqual(outcome, "missunit_dropped_store_ack")

    def test_writebuffer_return_not_evicted(self):
        req = [request_state() for _ in range(6)]
        adapter = [adapter_state() for _ in range(6)]
        adapter[2].update(adapter_write_ptr=1, input_rtype=MODULE.L15_ST_ACK)
        adapter[3].update(adapter_write_ptr=1, adapter_read_ptr=1,
                          front_rtype=MODULE.L15_ST_ACK)
        adapter[4].update(adapter_write_ptr=1, adapter_read_ptr=1)
        adapter[5].update(adapter_write_ptr=1, adapter_read_ptr=1)
        returned = [return_state() for _ in range(6)]
        returned[4]["wbuffer_rtrn_write_ptr"] = 1
        returned[5]["wbuffer_rtrn_write_ptr"] = 1
        outcome, _ = MODULE.classify_capture(req, adapter, returned, 1)
        self.assertEqual(outcome, "writebuffer_return_not_evicted")


if __name__ == "__main__":
    unittest.main()
