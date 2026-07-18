#!/usr/bin/env python3
"""Focused tests for the Build 92 udelay caller decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build92_udelay_caller.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build92", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build92DecodeTests(unittest.TestCase):
    def test_sign_extends_kernel_pointer(self):
        self.assertEqual(MODULE.sign_extend40(0xFF80401234), 0xFFFFFFFF80401234)

    def test_leaves_low_pointer_unsigned(self):
        self.assertEqual(MODULE.sign_extend40(0x0080001234), 0x0000000080001234)

    def test_validates_synchronized_trigger(self):
        payload = MODULE.BRANCH_PC_LOW24
        self.assertEqual(
            MODULE.validate_sync(
                [MODULE.BRANCH_PC], [[payload], [payload], [payload]], [0, 0, 0, 0]
            ),
            0,
        )


if __name__ == "__main__":
    unittest.main()
