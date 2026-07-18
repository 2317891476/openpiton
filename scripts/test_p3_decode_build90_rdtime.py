#!/usr/bin/env python3
"""Tests for the Build 90 rdtime ILA decoder."""

import csv
import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DECODER = ROOT / "scripts/p3_decode_build90_rdtime_csv.py"
SPEC = importlib.util.spec_from_file_location("p3_decode_build90", DECODER)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class Build90RdtimeDecoderTest(unittest.TestCase):
    def test_clean_smode_time_commit_passes(self) -> None:
        headers = [
            "Sample in Buffer",
            "Sample in Window",
            "TRIGGER",
            "commit_instr_id_commit[0][pc][63:0]",
            "commit_instr_id_commit[0][valid]",
            "commit_ack[0:0]",
            "csr_addr_ex_csr[11:0]",
            "csr_exception_csr_commit[cause][1:1]",
            "priv_lvl_q_reg[1:0]",
            "mcounteren[5:0]",
            "csr_regfile_i/cycle_q[63:0]",
        ]
        rows = [
            ["0", "0", "1", "ffffffff807d8a9e", "1", "1", "c01", "0", "1", "3f", "100"],
            ["1", "1", "0", "ffffffff807d8aa2", "1", "1", "c01", "0", "1", "3f", "101"],
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "capture.csv"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow(headers)
                writer.writerow(["UNSIGNED"] * len(headers))
                writer.writerows(rows)
            result = MODULE.decode(path)
        self.assertTrue(result["verdict"])
        self.assertEqual(result["target_commits"], 1)
        self.assertEqual(result["illegal_samples"], 0)

    def test_illegal_time_commit_fails(self) -> None:
        headers = [
            "Sample in Buffer",
            "Sample in Window",
            "TRIGGER",
            "commit_instr_id_commit[0][pc][63:0]",
            "commit_instr_id_commit[0][valid]",
            "commit_ack[0:0]",
            "csr_addr_ex_csr[11:0]",
            "csr_exception_csr_commit[cause][1:1]",
            "priv_lvl_q_reg[1:0]",
            "mcounteren[5:0]",
            "csr_regfile_i/cycle_q[63:0]",
        ]
        rows = [
            ["0", "0", "1", "ffffffff807d8a9e", "1", "1", "c01", "1", "1", "3f", "100"],
            ["1", "1", "0", "ffffffff807d8aa2", "1", "1", "c01", "0", "1", "3f", "101"],
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "capture.csv"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow(headers)
                writer.writerow(["UNSIGNED"] * len(headers))
                writer.writerows(rows)
            result = MODULE.decode(path)
        self.assertFalse(result["verdict"])


if __name__ == "__main__":
    unittest.main()
