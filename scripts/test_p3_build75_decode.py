#!/usr/bin/env python3
"""Focused tests for the Build 75 ILA decoder."""

import csv
import importlib.util
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build75_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build75", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build75DecodeTests(unittest.TestCase):
    def test_decodes_tag_stall_and_commit_pc(self):
        req = (0x8189B780 << 24) | (1 << 19) | (3 << 16) | (1 << 15) | (1 << 12) | (1 << 9)
        stall = (0x75 << 56) | (0x05 << 48) | (7 << 44) | (6 << 40) | (1 << 36)
        stall |= (1 << 10) | (1 << 9) | (1 << 6) | 1
        columns = {
            "p3_build75_noack_trigger": [1],
            "p3_build75_noack_count[8:0]": [256],
            "p3_build75_l15_req_bus[63:0]": [req],
            "p3_build75_l15_stall_bus[63:0]": [stall],
            "commit_instr_id_commit[0][pc][63:0]": [0xFFFFFFFF80123456],
            "commit_instr_id_commit[0][valid]": [1],
            "commit_instr_id_commit[0][fu][3:0]": [2],
            "commit_instr_id_commit[0][op][7:0]": [33],
            "commit_ack[0]": [0],
            "lsu_commit_ready_ex_commit": [0],
            "lsu_commit_commit_ex": [0],
        }
        decoded = MODULE.decode_sample(columns, 0)
        self.assertEqual(decoded["address"], 0x8189B780)
        self.assertEqual(decoded["tag"], 0x75)
        self.assertEqual(decoded["mshr_vals"], 0x05)
        active = MODULE.classify(decoded)
        self.assertEqual(active, ["matched-MSHR/tag conflict"])
        self.assertEqual(MODULE.validation_failures(decoded, active), [])

    def test_classifies_credit_stall(self):
        stall_bits = {name: 0 for name in MODULE.STALL_BITS}
        stall_bits["pcx_noc1_buffer_stall"] = 1
        decoded = {
            "req_flags": {"stall_s2": 0, "stall_s3": 0},
            "stall_bits": stall_bits,
        }
        self.assertEqual(MODULE.classify(decoded), ["NoC1 command/data credit stall"])

    def test_rejects_capture_without_concrete_blocker(self):
        decoded = {
            "tag": 0x75,
            "rqtype": 1,
            "raw": {"trigger": 1, "count": 256, "valid": 1, "fu": 2},
            "req_flags": {"pcx_val": 1, "pcx_ack": 0},
        }
        self.assertIn(
            "no concrete tag/index/S2-S3/MSHR/NoC1 blocker is active",
            MODULE.validation_failures(decoded, []),
        )

    def test_reads_the_csv_trigger_sample_not_the_last_sample(self):
        with tempfile.NamedTemporaryFile(mode="w", newline="", suffix=".csv") as stream:
            writer = csv.writer(stream)
            writer.writerow(["Sample in Buffer", "Sample in Window", "TRIGGER", "probe"])
            writer.writerow(["Radix - UNSIGNED", "UNSIGNED", "UNSIGNED", "HEX"])
            writer.writerow([0, 0, 0, "aa"])
            writer.writerow([1, 1, 1, "bb"])
            writer.writerow([2, 2, 0, "cc"])
            stream.flush()
            columns, count, trigger_sample = MODULE.read_capture(stream.name)
        self.assertEqual(count, 3)
        self.assertEqual(trigger_sample, 1)
        self.assertEqual(columns["probe"][trigger_sample], 0xBB)


if __name__ == "__main__":
    unittest.main()
