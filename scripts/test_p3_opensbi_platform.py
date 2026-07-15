#!/usr/bin/env python3
"""Focused regression tests for the P3 DTB/platform consistency checks."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

from p3_platform_config import Region, validate_load_layout
from p3_validate_tile_aperture import parameter_values, require_region


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent


class P3OpenSBIPlatformTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir_obj = tempfile.TemporaryDirectory(prefix="p3-platform-test-")
        self.tempdir = Path(self.tempdir_obj.name)
        self.initrd = self.tempdir / "rootfs.cpio.gz"
        self.initrd.write_bytes(b"P3TEST" * 683)

    def tearDown(self) -> None:
        self.tempdir_obj.cleanup()

    def run_checked(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            list(args),
            cwd=REPO_ROOT,
            check=True,
            text=True,
            capture_output=True,
        )

    def generate_dtb(self, harts: int, initrd_addr: int = 0x90000000) -> Path:
        dts = self.tempdir / f"p3_{harts}.dts"
        dtb = self.tempdir / f"p3_{harts}.dtb"
        self.run_checked(
            sys.executable,
            str(SCRIPT_DIR / "p3_generate_opensbi_dts.py"),
            "--harts",
            str(harts),
            "--initrd",
            str(self.initrd),
            "--initrd-addr",
            hex(initrd_addr),
            "--out",
            str(dts),
        )
        self.run_checked("dtc", "-I", "dts", "-O", "dtb", "-o", str(dtb), str(dts))
        return dtb

    def test_one_two_and_sixty_four_hart_dtbs_validate(self) -> None:
        for harts in (1, 2, 64):
            with self.subTest(harts=harts):
                dtb = self.generate_dtb(harts)
                self.run_checked(
                    sys.executable,
                    str(SCRIPT_DIR / "p3_validate_opensbi_dtb.py"),
                    "--dtb",
                    str(dtb),
                    "--harts",
                    str(harts),
                    "--initrd",
                    str(self.initrd),
                    "--initrd-addr",
                    "0x90000000",
                )
                end_cells = self.run_checked(
                    "fdtget", "-tx", str(dtb), "/chosen", "linux,initrd-end"
                ).stdout.split()
                initrd_end = (int(end_cells[0], 16) << 32) | int(end_cells[1], 16)
                self.assertEqual(initrd_end, 0x90000000 + self.initrd.stat().st_size)

    def test_build66_flat_image_places_and_reads_back_components(self) -> None:
        fw = self.tempdir / "fw_jump.bin"
        image = self.tempdir / "Image"
        fw.write_bytes(b"FW66" * 1024)
        image.write_bytes(b"LINUX66" * 2048)
        dtb = self.generate_dtb(1, initrd_addr=0x81700000)
        out = self.tempdir / "build66-flat.img"

        self.run_checked(
            sys.executable,
            str(SCRIPT_DIR / "p3_make_build66_opensbi_flat_image.py"),
            "--fw",
            str(fw),
            "--image",
            str(image),
            "--dtb",
            str(dtb),
            "--initrd",
            str(self.initrd),
            "--out",
            str(out),
            "--size-mib",
            "40",
        )

        partition_offset = 2048 * 512
        with out.open("rb") as packed:
            packed.seek(partition_offset)
            self.assertEqual(packed.read(fw.stat().st_size), fw.read_bytes())
            packed.seek(partition_offset + 0x200000)
            self.assertEqual(packed.read(image.stat().st_size), image.read_bytes())
            packed.seek(partition_offset + 0x1600000)
            self.assertEqual(packed.read(dtb.stat().st_size), dtb.read_bytes())
            packed.seek(partition_offset + 0x1700000)
            self.assertEqual(
                packed.read(self.initrd.stat().st_size), self.initrd.read_bytes()
            )
        manifest = out.with_suffix(".img.manifest").read_text(encoding="ascii")
        self.assertIn("copy_blocks=65536", manifest)
        self.assertIn("component name=initrd load_addr=0x81700000", manifest)

    def test_build66_flat_image_rejects_component_outside_copy_window(self) -> None:
        fw = self.tempdir / "fw-bad.bin"
        image = self.tempdir / "image-bad.bin"
        fw.write_bytes(b"FW")
        image.write_bytes(b"IMAGE")
        dtb = self.generate_dtb(1, initrd_addr=0x81700000)
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "p3_make_build66_opensbi_flat_image.py"),
                "--fw",
                str(fw),
                "--image",
                str(image),
                "--dtb",
                str(dtb),
                "--initrd",
                str(self.initrd),
                "--out",
                str(self.tempdir / "bad-flat.img"),
                "--dtb-addr",
                "0x82000000",
                "--size-mib",
                "40",
            ],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the Build 66 copy window", result.stderr)

    def test_wrong_hardware_map_is_rejected(self) -> None:
        dtb = self.generate_dtb(2)
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "p3_validate_opensbi_dtb.py"),
                "--dtb",
                str(dtb),
                "--device-map",
                str(REPO_ROOT / "piton/design/xilinx/a7203x/devices_ariane.xml"),
                "--harts",
                "2",
            ],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("memory", result.stderr.lower())

    def test_inconsistent_timebase_is_rejected(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "p3_generate_opensbi_dts.py"),
                "--harts",
                "2",
                "--timebase-frequency",
                "1000000",
                "--out",
                str(self.tempdir / "bad-timebase.dts"),
            ],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disagrees", result.stderr)

    def test_component_overlap_and_out_of_range_are_rejected(self) -> None:
        memory = Region("mem", 0x80000000, 0x80000000)
        with self.assertRaisesRegex(ValueError, "overlap"):
            validate_load_layout(
                [("fw", 0x80000000, 0x200000), ("linux", 0x80100000, 0x1000)],
                memory,
            )
        with self.assertRaisesRegex(ValueError, "outside DDR"):
            validate_load_layout([("initrd", 0x100000000, 0x1000)], memory)

    def test_stale_one_gib_tile_aperture_is_rejected(self) -> None:
        tile = """
            .ExecuteRegionAddrBase ({64'h80000000}),
            .ExecuteRegionLength ({64'h40000000}),
            .CachedRegionAddrBase ({64'h80000000}),
            .CachedRegionLength ({64'h40000000})
        """
        with self.assertRaisesRegex(ValueError, "length mismatch"):
            require_region(
                parameter_values(tile, "ExecuteRegionAddrBase"),
                parameter_values(tile, "ExecuteRegionLength"),
                0x80000000,
                0x80000000,
                "CVA6 execute aperture",
            )


if __name__ == "__main__":
    unittest.main()
