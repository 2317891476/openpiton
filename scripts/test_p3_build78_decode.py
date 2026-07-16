#!/usr/bin/env python3
"""Focused tests for the Build 78 store-path decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build78_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build78", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build78DecodeTests(unittest.TestCase):
    def test_decodes_core_l15_history_bus(self):
        raw = (0x8185DC80 << 24) | (0x12 << 19) | (3 << 16) | 0x85
        decoded = MODULE.decode_core_bus(raw)
        self.assertEqual(decoded["last_l15_addr"], 0x8185DC80)
        self.assertEqual(decoded["last_l15_rqtype"], 0x12)
        self.assertEqual(decoded["last_l15_size"], 3)
        self.assertEqual(decoded["flags"], 0x85)

    def test_decodes_store_path_payload(self):
        raw = (
            0
            | (0 << 1)
            | (3 << 2)
            | (2 << 5)
            | (0xA5 << 7)
            | (0x81 << 15)
            | (2 << 23)
            | (3 << 25)
            | (5 << 28)
            | (7 << 31)
            | (1 << 34)
            | (1 << 35)
        )
        decoded = MODULE.decode_store_diag(raw)
        self.assertEqual(decoded["no_st_pending_ex"], 0)
        self.assertEqual(decoded["dcache_wbuffer_empty"], 0)
        self.assertEqual(decoded["commit_status_count"], 3)
        self.assertEqual(decoded["commit_read_pointer"], 2)
        self.assertEqual(decoded["wbuffer_valid"], 0xA5)
        self.assertEqual(decoded["wbuffer_dirty"], 0x81)
        self.assertEqual(decoded["tx_valid"], 2)
        self.assertEqual(decoded["tx0_pointer"], 3)
        self.assertEqual(decoded["tx1_pointer"], 5)
        self.assertEqual(decoded["dirty_pointer"], 7)
        self.assertEqual(decoded["evict"], 1)
        self.assertEqual(decoded["filler"], 1)

    def test_extracts_one_vector_probe(self):
        columns = {
            "u_bd/p3_dbg_core_bus64_i_1[63:0]": [0x1234, 0x5678],
            "unrelated": [0, 0],
        }
        self.assertEqual(
            MODULE.one_vector_probe(columns, "p3_dbg_core_bus64_i_1"),
            [0x1234, 0x5678],
        )

    def test_reports_set_bits(self):
        self.assertEqual(MODULE.set_bits(0xA5, 8), [0, 2, 5, 7])

    def test_classifies_fully_drained_idle_core(self):
        core = MODULE.decode_core_bus((0xF4 << 8) | 0x07)
        commit = {
            "valid": 0,
            "ack": 0,
            "fu": 1,
            "op": 0x25,
            "stall_s1": 0,
            "stall_s2": 0,
            "stall_s3": 0,
        }
        diag = MODULE.decode_store_diag((1 << 0) | (1 << 1))
        self.assertEqual(
            MODULE.classify_outcome(core, commit, diag), "drained_idle"
        )

    def test_classifies_blocked_fence_request(self):
        core = MODULE.decode_core_bus(0x80)
        commit = {
            "valid": 1,
            "ack": 0,
            "fu": 6,
            "op": 0x1C,
            "stall_s1": 1,
            "stall_s2": 0,
            "stall_s3": 0,
        }
        diag = MODULE.decode_store_diag(0)
        self.assertEqual(
            MODULE.classify_outcome(core, commit, diag), "blocked_fence"
        )


if __name__ == "__main__":
    unittest.main()
