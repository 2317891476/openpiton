#!/usr/bin/env python3
"""Focused structural and truth-table checks for the Build 88 ECO."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "p3_build88_time_csr_local_eco.tcl"


class Build88TimeCsrLocalEcoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text()

    def test_time_address_truth_tables(self):
        low_init = 0x0000000000000002
        high_init = 0x0001000000000000
        for address in range(1 << 12):
            low = (low_init >> (address & 0x3F)) & 1
            high = (high_init >> ((address >> 6) & 0x3F)) & 1
            self.assertEqual(bool(low and high), address == 0xC01)

    def test_mux_truth_tables(self):
        mux_init = 0xCA
        zero_init = 0x2
        for select in (0, 1):
            for old in (0, 1):
                for new in (0, 1):
                    mux_index = old | (new << 1) | (select << 2)
                    self.assertEqual(
                        (mux_init >> mux_index) & 1,
                        new if select else old,
                    )
                zero_index = old | (select << 1)
                self.assertEqual((zero_init >> zero_index) & 1, old & ~select)

    def test_uses_only_csr_local_leaf_boundary(self):
        self.assertIn("csr_rdata_csr_commit", self.text)
        self.assertIn("commit-stage CSR read-data bit", self.text)
        self.assertIn("csr_exception_csr_commit", self.text)
        self.assertNotIn("wdata_commit_id\\[", self.text)
        self.assertNotIn("commit_instr_id_commit", self.text)

    def test_advanced_flow_and_fail_closed_count(self):
        self.assertIn("place_design -eco -no_timing_driven", self.text)
        self.assertIn("expected 68", self.text)
        self.assertIn("global wdata_commit_id network: unchanged", self.text)
        self.assertIn("30 MHz / 128 = 234375 Hz", self.text)


if __name__ == "__main__":
    unittest.main()
