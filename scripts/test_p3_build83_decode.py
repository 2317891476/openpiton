#!/usr/bin/env python3
"""Focused tests for the Build 83 orphan return-ID decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build83_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build83", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def state(**updates):
    value = {
        "return_status": 0,
        "return_read_ptr": 0,
        "return_mem0_tid": 0,
        "return_mem1_tid": 1,
        "tx_valid": 1,
        "wreturn_status": 0,
        "wreturn_write_ptr": 0,
    }
    value.update(updates)
    return value


def adapter(**updates):
    value = {
        "adapter_write_ptr": 0,
        "adapter_input_rtype": 0,
        "adapter_input_tid": 0,
    }
    value.update(updates)
    return value


class Build83DecodeTests(unittest.TestCase):
    def test_common_head_and_orphan(self):
        value = 1 | (1 << 3) | (1 << 5)
        decoded = MODULE.decode_common(value)
        self.assertEqual(MODULE.head_tid(decoded), 1)
        self.assertTrue(MODULE.is_orphan(decoded))

    def test_late_duplicate_store_ack(self):
        states = [state(tx_valid=2), state(return_status=1, wreturn_status=1,
                                          wreturn_write_ptr=1, tx_valid=2)]
        adapters = [adapter(), adapter(adapter_write_ptr=1,
                                       adapter_input_rtype=MODULE.L15_ST_ACK,
                                       adapter_input_tid=0)]
        self.assertEqual(
            MODULE.classify_orphan(states, adapters, 1),
            "late_or_duplicate_store_ack_for_inactive_slot",
        )

    def test_queued_orphan_after_pop(self):
        states = [state(return_status=2, wreturn_status=2, tx_valid=2),
                  state(return_status=1, return_read_ptr=1,
                        wreturn_status=1, tx_valid=1)]
        adapters = [adapter(), adapter()]
        self.assertEqual(
            MODULE.classify_orphan(states, adapters, 1),
            "queued_orphan_revealed_after_prior_return_pop",
        )


if __name__ == "__main__":
    unittest.main()
