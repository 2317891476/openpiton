#!/usr/bin/env python3
"""Focused checks for the Build 89 issue-stage boundary CSR_TIME ECO."""

import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name(
    "p3_build89_time_csr_boundary_eco.tcl"
)


def lut(init: int, inputs: int) -> int:
    return (init >> inputs) & 1


class Build89TimeCsrBoundaryEcoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_selector_matches_only_committing_csr_time(self) -> None:
        for address in range(1 << 12):
            low = lut(0x0000000000000002, address & 0x3F)
            high = lut(0x0001000000000000, (address >> 6) & 0x3F)
            address_selected = lut(0x8, low | (high << 1))
            for valid in (0, 1):
                for fu in range(16):
                    commit_selected = lut(0x00002000, valid | (fu << 1))
                    selected = lut(
                        0x8, address_selected | (commit_selected << 1)
                    )
                    self.assertEqual(
                        selected,
                        address == 0xC01 and valid == 1 and fu == 6,
                        (hex(address), valid, fu),
                    )

    def test_mux_and_exception_truth_tables(self) -> None:
        for old in (0, 1):
            for new in (0, 1):
                for selected in (0, 1):
                    self.assertEqual(
                        lut(0xCA, old | (new << 1) | (selected << 2)),
                        new if selected else old,
                    )
            for selected in (0, 1):
                self.assertEqual(
                    lut(0x2, old | (selected << 1)),
                    0 if selected else old,
                )

    def test_reconnects_only_issue_stage_boundary_pins(self) -> None:
        self.assertIn(
            '"${issue}/wdata_commit_id\\[0\\]_27\\[${bit}\\]"',
            self.text,
        )
        self.assertIn(
            '"${issue}/csr_exception_csr_commit\\[cause\\]\\[0\\]"',
            self.text,
        )
        self.assertNotIn("get_nets -quiet -segments", self.text)
        self.assertNotIn("${scoreboard}/wdata_commit_id", self.text)
        self.assertNotIn("${scoreboard}/csr_exception_csr_commit", self.text)

    def test_advanced_flow_and_fail_closed_count(self) -> None:
        self.assertIn("place_design -eco -no_timing_driven", self.text)
        self.assertIn("expected 70", self.text)
        self.assertIn("segmented-net fanout: unchanged", self.text)
        self.assertIn("30 MHz / 128 = 234375 Hz", self.text)


if __name__ == "__main__":
    unittest.main()
