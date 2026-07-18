#!/usr/bin/env python3
"""Focused tests for the Build 91 udelay-value decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build91_udelay_values.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build91", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build91DecodeTests(unittest.TestCase):
    def test_classifies_correct_waiting_loop(self):
        self.assertEqual(MODULE.classify(100, 50, 120, 20), "UDELAY_STILL_WAITING")

    def test_classifies_branch_that_should_exit(self):
        self.assertEqual(MODULE.classify(100, 20, 120, 20), "BRANCH_SHOULD_EXIT")

    def test_classifies_sub_result_mismatch(self):
        self.assertEqual(
            MODULE.classify(100, 50, 120, 19), "SUB_OR_GPR_RESULT_MISMATCH"
        )

    def test_validates_synchronized_trigger(self):
        payload = MODULE.BRANCH_PC_LOW24
        control = [MODULE.BRANCH_PC]
        payloads = [[payload], [payload], [payload]]
        self.assertEqual(MODULE.validate_sync(control, payloads, [0, 0, 0, 0]), 0)


if __name__ == "__main__":
    unittest.main()
