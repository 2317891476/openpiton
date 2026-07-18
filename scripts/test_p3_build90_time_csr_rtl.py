#!/usr/bin/env python3
"""Structural gates for the clean-RTL Build 90 TIME flow."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "scripts/p3_build90_time_csr_rtl.tcl"
PREPARE = ROOT / "scripts/p3_prepare_build90_time_csr_rtl.tcl"
DEBUG = ROOT / "scripts/p3_build90_insert_debug.tcl"
COMMON = ROOT / "scripts/p3_build52_sd_cd_mask.tcl"


class Build90TimeCsrRtlTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.build = BUILD.read_text(encoding="utf-8")
        cls.prepare = PREPARE.read_text(encoding="utf-8")
        cls.debug = DEBUG.read_text(encoding="utf-8")
        cls.common = COMMON.read_text(encoding="utf-8")

    def test_build_enables_only_intended_time_rtl_path(self) -> None:
        self.assertIn("P3_TIME_CSR_DIV128", self.build)
        self.assertIn("PITON_X_TILES) 1", self.build)
        self.assertIn("PITON_Y_TILES) 1", self.build)
        self.assertIn("PITON_NUM_TILES) 1", self.build)
        self.assertIn("P3_SELF_CONTAINED_SOURCES) 1", self.build)
        self.assertNotIn("wdata_commit_id", self.build)

    def test_prepare_override_is_fail_closed_and_sanitizes_snapshot(self) -> None:
        self.assertIn("P3_BUILD52_PREPARE_TCL", self.common)
        self.assertIn("missing Build 52 prepare script", self.common)
        self.assertIn("/mnt/[string tolower $drive]/$rest", self.common)
        self.assertIn("git -C ${plic_repo_wsl} show HEAD", self.prepare)
        self.assertIn("ip_re_o = '0;", self.prepare)
        self.assertIn("snapshot PLIC restore produced an empty file", self.prepare)
        self.assertIn("csr_rdata = cycle_q >> 7", self.prepare)
        self.assertIn("p3_prepare_build52_sd_cd_mask_ila.tcl", self.prepare)

    def test_debug_ila_observes_causal_commit_and_csr_state(self) -> None:
        for token in (
            "commit PC",
            "commit valid",
            "commit ack",
            "commit FU",
            "commit op",
            "CSR address",
            "CSR illegal flag",
            "priv_lvl_q_reg",
            "mcounteren_q_reg",
            "cycle_q_reg",
        ):
            self.assertIn(token, self.debug)
        self.assertIn("C_DATA_DEPTH 4096", self.debug)
        self.assertIn("C_NUM_OF_PROBES 10", self.debug)

    def test_build_wires_custom_prepare_and_post_synth_debug(self) -> None:
        self.assertIn("p3_prepare_build90_time_csr_rtl.tcl", self.build)
        self.assertIn("p3_build90_insert_debug.tcl", self.build)
        self.assertIn("u_ila_build90", self.build)
        self.assertIn("p3_rebuild_build66_normal_spi_sd_boot.sh", self.build)

    def test_self_contained_validation_allows_only_current_p3b_workspace(self) -> None:
        self.assertIn("proc p3_has_external_forbidden_path", self.common)
        self.assertIn(
            'set project_prefix "[string tolower [p3_slash_path $project_dir]]/"',
            self.common,
        )
        self.assertIn(
            "p3_has_external_forbidden_path $data $pattern $project_dir",
            self.common,
        )
        self.assertIn(
            "p3_has_external_forbidden_path $file_path $pattern $project_dir",
            self.common,
        )
        self.assertIn(
            "p3_has_external_forbidden_path $inc_path $pattern $project_dir",
            self.common,
        )

    def test_resumed_build_refreshes_tile_dependent_snapshot_outputs(self) -> None:
        self.assertIn("proc p3_sync_generated_pyhp_snapshot", self.common)
        self.assertIn(r"regexp {^(.*)\.tmp\.v$}", self.common)
        self.assertIn(r"regexp {^(.*)\.tmp\.h$}", self.common)
        self.assertIn('set template_rel "${stem}.v.pyv"', self.common)
        self.assertIn('set template_rel "${stem}.h.pyv"', self.common)
        self.assertIn('set staged_wsl "${snapshot_wsl}.p3new"', self.common)
        self.assertIn("Refreshed ${refreshed_count} self-contained PyHP outputs", self.common)
        self.assertIn(
            "if {!$run_create && $p3_self_contained_sources}", self.common
        )
        self.assertIn(
            "p3_sync_generated_pyhp_snapshot $repo_dir $project_dir", self.common
        )


if __name__ == "__main__":
    unittest.main()
