#!/usr/bin/env python3
"""Focused tests for the Build 80 synchronized trap decoder."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("p3_decode_build80_ila_csv.py")
SPEC = importlib.util.spec_from_file_location("p3_decode_build80", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Build80DecodeTests(unittest.TestCase):
    def test_decodes_packed_trap_state(self):
        value = (
            1
            | (1 << 1)
            | (1 << 2)
            | (0 << 3)
            | (0x6 << 4)
            | (0x20 << 8)
            | (0xC01 << 16)
            | (1 << 28)
            | (2 << 30)
            | (0 << 36)
            | (0x02 << 37)
            | (1 << 58)
            | (1 << 59)
            | (1 << 63)
        )
        state = MODULE.decode_packed_state(value)
        self.assertEqual(state["ex_commit_valid"], 1)
        self.assertEqual(state["csr_illegal"], 1)
        self.assertEqual(state["fu"], 0x6)
        self.assertEqual(state["op"], 0x20)
        self.assertEqual(state["csr_addr"], 0xC01)
        self.assertEqual(state["priv"], 1)
        self.assertEqual(state["mcause"], 2)
        self.assertEqual(state["mcounteren"], 2)
        self.assertEqual(state["trigger"], 1)

    def test_decodes_rdtime_instruction(self):
        decoded = MODULE.decode_csr_instruction(0xC0102573)
        self.assertTrue(decoded["is_csr"])
        self.assertEqual(decoded["operation"], "CSRRS")
        self.assertEqual(decoded["rd"], 10)
        self.assertEqual(decoded["rs1_or_zimm"], 0)
        self.assertEqual(decoded["csr"], 0xC01)

    def test_reconstructs_ltx_mapped_vector_lsb_first(self):
        value = 0xFEDCBA9876543210
        columns = {}
        bit_to_net = {}
        for bit in range(64):
            name = f"u_bd/core/net_{bit}"
            bit_to_net[bit] = name
            columns[name] = [(value >> bit) & 1]
        self.assertEqual(
            MODULE.reconstruct_from_net_map(columns, bit_to_net, 64), [value]
        )

    def test_builds_axis0_and_vector_maps_from_ltx_positions(self):
        layouts = {
            "u_bd/openpiton_top_i/axis_ila_0": {(0, 0): "trigger"},
            "u_bd/openpiton_top_i/axis_ila_1": {},
            "u_bd/openpiton_top_i/axis_ila_2": {},
            "u_bd/openpiton_top_i/axis_ila_3": {},
        }
        for word in range(4):
            for bit in range(16):
                layouts["u_bd/openpiton_top_i/axis_ila_0"][(word + 1, bit)] = (
                    f"pc_{word * 16 + bit}"
                )
        for index in range(1, 4):
            key = f"u_bd/openpiton_top_i/axis_ila_{index}"
            layouts[key] = {(0, bit): f"ila{index}_{bit}" for bit in range(64)}
        maps = MODULE.build_vector_maps(layouts)
        self.assertEqual(maps["ila0_trigger"], {0: "trigger"})
        self.assertEqual(maps["pc"][0], "pc_0")
        self.assertEqual(maps["pc"][63], "pc_63")
        self.assertEqual(maps["ila2"][37], "ila2_37")

    def test_requires_common_trigger_alignment(self):
        series = [[0, 0, 1, 1] for _ in range(4)]
        self.assertEqual(
            MODULE.validate_synchronized_capture(series, [2, 2, 2, 2]), 2
        )
        series[3] = [0, 1, 1, 1]
        with self.assertRaisesRegex(ValueError, "not synchronized"):
            MODULE.validate_synchronized_capture(series, [2, 2, 2, 2])

    def test_finds_repeated_rising_edges(self):
        self.assertEqual(MODULE.rising_edges([0, 1, 1, 0, 1, 0]), [1, 4])

    def test_csr_address_cross_check_window(self):
        states = [{"csr_addr": 0}, {"csr_addr": 0xC01}, {"csr_addr": 0xC01}]
        self.assertEqual(MODULE.find_csr_match(states, 0xC01, 0, 2), [1, 2])
        self.assertEqual(MODULE.find_csr_match(states, 0xC00, 0, 2), [])


if __name__ == "__main__":
    unittest.main()
