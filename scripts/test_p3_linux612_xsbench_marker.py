#!/usr/bin/env python3
"""Static contracts for the Linux 6.12 XSBench stage-marker image."""

from __future__ import annotations

from pathlib import Path
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent


class P3Linux612XsbenchMarkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.instrumenter = (SCRIPT_DIR / "p3_instrument_xsbench.py").read_text()
        cls.marker_source = (SCRIPT_DIR / "p3_xsbench_markers.c").read_text()
        cls.builder = (
            SCRIPT_DIR / "p3_build_xsbench_stage_markers.sh"
        ).read_text()
        cls.initrd_builder = (
            SCRIPT_DIR / "p3_make_linux612_mpi_initrd.sh"
        ).read_text()
        cls.init = (
            SCRIPT_DIR / "p3_linux612_xsbench_marker_init.sh"
        ).read_text()
        cls.image_builder = (
            SCRIPT_DIR
            / "p3_prepare_build66_1hart_linux612_xsbench_marker_image.sh"
        ).read_text()

    def test_markers_bypass_stdio_buffering(self) -> None:
        self.assertIn("write(STDOUT_FILENO", self.marker_source)
        self.assertIn("__attribute__((constructor(101)))", self.marker_source)
        for forbidden in ("printf(", "fprintf(", "puts(", "malloc("):
            self.assertNotIn(forbidden, self.marker_source)

    def test_instrumentation_is_source_pinned_and_fail_closed(self) -> None:
        self.assertIn("replace_once", self.instrumenter)
        self.assertIn("expected one instrumentation anchor", self.instrumenter)
        self.assertIn(
            'source_commit="ba08e5221af6106252b866e50ea123c69d31a4e2"',
            self.builder,
        )
        self.assertIn(
            'reference_sha256="1e896862da3294129c02bcbd8dfbd89fe70e093ef4c03f430882b6fede110930"',
            self.builder,
        )

    def test_markers_cover_runtime_grid_and_simulation_boundaries(self) -> None:
        for marker in (
            "P3_XS M-1 constructor",
            "P3_XS M00 main_entry",
            "P3_XS M21 openmp_set_done",
            "P3_XS G13 nuclide_fill_begin",
            "P3_XS G20 nuclide_sort_begin",
            "P3_XS U30 unionized_sort_begin",
            "P3_XS U60 index_fill_begin",
            "P3_XS H10 history_loop_begin",
            "P3_XS H11 particles_done=",
            "P3_XS M99 exit_status=",
        ):
            self.assertIn(marker, self.instrumenter + self.marker_source)

    def test_builder_preserves_reference_flags_and_scans_custom_csr(self) -> None:
        for flag in (
            "-std=gnu99",
            "-flto",
            "-fopenmp",
            "-DOPENMP",
            "-O3",
            "-static",
        ):
            self.assertIn(flag, self.builder)
        self.assertIn("XSBench_reference_rebuilt", self.builder)
        self.assertIn("0x701", self.builder)

    def test_initrd_override_is_pairwise_hash_asserted(self) -> None:
        self.assertIn("P3_LINUX612_INIT_SOURCE", self.initrd_builder)
        self.assertIn("P3_LINUX612_XSBENCH_BINARY", self.initrd_builder)
        self.assertIn("P3_LINUX612_XSBENCH_SHA256", self.initrd_builder)
        self.assertIn(
            'install -m 0755 "$xsbench_binary" "$root/root/XSBench_marked"',
            self.initrd_builder,
        )

    def test_init_runs_exact_case_automatically_after_system_smoke(self) -> None:
        smoke = self.init.index("/usr/bin/p3_mpi_system_smoke")
        run = self.init.index(
            "/root/XSBench_marked -t 1 -s small -p 1000 -l 1"
        )
        shell = self.init.index("exec /bin/sh")
        self.assertLess(smoke, run)
        self.assertLess(run, shell)

    def test_image_reuses_board_validated_stack_and_is_compressed(self) -> None:
        for digest in (
            "fbbf1cc1c1ec35d7e90584ed9c078045678a62282ec7c07f60c4f9d35857eb8e",
            "f6ef8f610c992edd8458c0a8b0848e48604f0f91a654381235ebacef84e11c76",
            "ee30fe4d052c763c9fc2fa72bf71cc8363173ad210ea8fb106533ac3081dd62d",
            "cc8daa214860651e2da283185ae843ba64baaf56892859b058fbc049450fbcb6",
        ):
            self.assertIn(digest, self.image_builder)
        self.assertIn('gzip -9n -c "$sd_img"', self.image_builder)
        self.assertIn('gzip -dc "$sd_img.gz" | sha256sum', self.image_builder)
        self.assertIn("p3_make_build66_opensbi_flat_image.py", self.image_builder)


if __name__ == "__main__":
    unittest.main()
