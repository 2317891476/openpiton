#!/usr/bin/env python3
"""Focused tests for the Build 76 ECO ILA decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build76_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build76", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build76DecodeTests(unittest.TestCase):
    def test_reconstructs_split_probe_lsb_first(self):
        value = 0x8185DC80
        columns = {
            f"u_bd/p3_build76_axis_ila_1_probe0_{bit}": [(value >> bit) & 1]
            for bit in range(64)
        }
        self.assertEqual(
            MODULE.reconstruct_split_probe(columns, "axis_ila_1_probe0", 64),
            [value],
        )

    def test_decodes_packed_commit_state(self):
        raw = 1 | (2 << 2) | (0x21 << 6) | (0x480 << 14) | (1 << 25)
        decoded = MODULE.decode_status(raw)
        self.assertEqual(decoded["valid"], 1)
        self.assertEqual(decoded["ack"], 0)
        self.assertEqual(decoded["fu"], 2)
        self.assertEqual(decoded["op"], 0x21)
        self.assertEqual(decoded["lsu_addr_low"], 0x480)
        self.assertEqual(decoded["stall_s1"], 1)

    def test_rejects_missing_split_bit(self):
        columns = {
            f"axis_ila_2_probe0_{bit}": [0]
            for bit in range(27)
        }
        with self.assertRaisesRegex(ValueError, "missing=\\[27\\]"):
            MODULE.reconstruct_split_probe(columns, "axis_ila_2_probe0", 28)

    def test_accepts_build77_commit_valid_alias(self):
        columns = {
            **{
                f"axis_ila_2_probe0_{bit}": [0]
                for bit in range(1, 28)
            },
            "u_bd/p3_build77_commit_valid": [1],
        }
        values = MODULE.reconstruct_split_probe(
            columns,
            "axis_ila_2_probe0",
            28,
            aliases={0: "p3_build77_commit_valid"},
        )
        self.assertEqual(values, [1])

    def test_classifies_blocked_fence_as_pending_store(self):
        status = MODULE.decode_status(
            1 | (0x6 << 2) | (0x1C << 6) | (1 << 25)
        )
        conclusions = MODULE.classify_status(status)
        self.assertTrue(any("earlier store has not drained" in text for text in conclusions))
        self.assertTrue(any("individual S1 blocker" in text for text in conclusions))

    def test_classifies_blocked_store_as_lsu_backpressure(self):
        status = MODULE.decode_status(0)
        status.update({"valid": 1, "ack": 0, "fu": 0x2, "op": 0x24})
        conclusions = MODULE.classify_status(status)
        self.assertEqual(len(conclusions), 1)
        self.assertIn("commit_lsu_ready_i=0", conclusions[0])


if __name__ == "__main__":
    unittest.main()
