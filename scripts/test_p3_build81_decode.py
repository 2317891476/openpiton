#!/usr/bin/env python3
"""Focused tests for the Build 81 write-buffer decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build81_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build81", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build81DecodeTests(unittest.TestCase):
    def test_decodes_control_layout(self):
        value = (
            1 | (0x6 << 2) | (0x1C << 6) | (1 << 14) |
            (0xA5 << 16) | (2 << 24) | (3 << 26) | (6 << 29) |
            (0x0F << 32) | (0xF0 << 40) | (1 << 48) |
            (0x43 << 53) | (1 << 60) | (5 << 61)
        )
        state = MODULE.decode_control(value)
        self.assertEqual(state["commit_valid"], 1)
        self.assertEqual(state["commit_ack"], 0)
        self.assertEqual(state["fu"], 0x6)
        self.assertEqual(state["op"], 0x1C)
        self.assertEqual(state["checked"], 0xA5)
        self.assertEqual(state["tx_valid"], 2)
        self.assertEqual((state["tx0_ptr"], state["tx1_ptr"]), (3, 6))
        self.assertEqual((state["tx0_be"], state["tx1_be"]), (0x0F, 0xF0))
        self.assertEqual(state["checked_duplicate"], 0x43)
        self.assertEqual(state["load_miss_req"], 1)
        self.assertEqual(state["dirty_ptr"], 5)

    def test_splits_entry_byte_masks(self):
        value = sum((entry + 1) << (entry * 8) for entry in range(8))
        self.assertEqual(MODULE.entry_masks(value), list(range(1, 9)))

    def test_classifies_unaccepted_dirty_request(self):
        state = {
            "commit_valid": 1, "commit_ack": 0, "fu": 0x6, "op": 0x1C,
            "no_st_pending": 1, "wbuffer_empty": 0, "miss_req": 1,
            "dirty_rd_en": 0, "tx_valid": 0, "evict": 0,
        }
        self.assertEqual(
            MODULE.classify(state, [0xFF] + [0] * 7, [0] * 8),
            "miss_not_accepted",
        )

    def test_classifies_inflight_transaction(self):
        state = {
            "commit_valid": 1, "commit_ack": 0, "fu": 0x6, "op": 0x1C,
            "no_st_pending": 1, "wbuffer_empty": 0, "miss_req": 0,
            "dirty_rd_en": 0, "tx_valid": 1, "evict": 0,
        }
        self.assertEqual(
            MODULE.classify(state, [0] * 8, [0xFF] + [0] * 7),
            "inflight_not_evicted",
        )


if __name__ == "__main__":
    unittest.main()
