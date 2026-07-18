#!/usr/bin/env python3
"""Structural gates for the Build 90 board rdtime trigger."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "scripts/p3_ila_capture_build90_rdtime.tcl"


class Build90RdtimeCaptureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.capture = CAPTURE.read_text(encoding="utf-8")

    def test_uses_clean_rtl_ila_and_exact_linux_pc(self) -> None:
        self.assertIn("CELL_NAME == u_ila_build90", self.capture)
        self.assertIn('trigger_pc_hex "ffffffff807d8a9e"', self.capture)
        self.assertIn("commit_instr_id_commit[0][pc]", self.capture)
        self.assertIn('"eq64\'h${trigger_pc_hex}"', self.capture)

    def test_capture_depth_and_output_are_fail_closed(self) -> None:
        self.assertIn("CONTROL.DATA_DEPTH 4096", self.capture)
        self.assertIn("CONTROL.TRIGGER_POSITION 512", self.capture)
        self.assertIn("required exact $kind matched", self.capture)
        self.assertIn("Build 90 rdtime CSV is missing or empty", self.capture)


if __name__ == "__main__":
    unittest.main()
