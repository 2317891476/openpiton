#!/usr/bin/env python3
"""Static contract tests for the Build 66 OpenSBI/Linux 6.12 flow."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
BUILD_SCRIPT = SCRIPT_DIR / "p3_prepare_build66_1hart_linux612_image.sh"
CONFIG_FRAGMENT = SCRIPT_DIR / "p3_linux612_build66.config"
FDT_PATCH = SCRIPT_DIR / "p3_opensbi_fixed_fdt_noreloc.patch"


def enabled_settings(text: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    for line in text.splitlines():
        match = re.fullmatch(r"(CONFIG_[A-Z0-9_]+)=(.*)", line)
        if match:
            settings[match.group(1)] = match.group(2)
    return settings


def disabled_settings(text: str) -> set[str]:
    settings = set()
    for line in text.splitlines():
        match = re.fullmatch(r"# (CONFIG_[A-Z0-9_]+) is not set", line)
        if match:
            settings.add(match.group(1))
    return settings


class P3Linux612Build66Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = BUILD_SCRIPT.read_text(encoding="utf-8")
        cls.fragment = CONFIG_FRAGMENT.read_text(encoding="utf-8")
        cls.patch = FDT_PATCH.read_text(encoding="utf-8")

    def test_version_and_external_artifacts_are_hash_pinned(self) -> None:
        self.assertIn('linux_version="6.12.98"', self.script)
        for digest in (
            "a62b6a2d207ff72510e5f47156b7078e1e71797357412411b8e4fff97fc8f4c7",
            "f6ef8f610c992edd8458c0a8b0848e48604f0f91a654381235ebacef84e11c76",
            "60aaf85d266a77cce0c2cf59a22221bcc321c2f15fd36ce242a092e0b516f142",
            "ee30fe4d052c763c9fc2fa72bf71cc8363173ad210ea8fb106533ac3081dd62d",
            "7b9c348e4d2695dfd90f700aabc8e4eee66288d07dd7a4c81ea636e33d2aeaaf",
        ):
            self.assertIn(digest, self.script)

    def test_config_uses_modern_sbi_hsm_capable_kernel(self) -> None:
        enabled = enabled_settings(self.fragment)
        disabled = disabled_settings(self.fragment)
        self.assertEqual(enabled["CONFIG_SMP"], "y")
        self.assertEqual(enabled["CONFIG_NR_CPUS"], "64")
        self.assertEqual(enabled["CONFIG_RISCV_SBI"], "y")
        self.assertEqual(enabled["CONFIG_RISCV_ISA_FALLBACK"], "y")
        self.assertEqual(enabled["CONFIG_EXPERT"], "y")
        self.assertIn("CONFIG_RISCV_SBI_V01", disabled)
        self.assertIn("CONFIG_RISCV_BOOT_SPINWAIT", disabled)
        self.assertIn("CONFIG_CPU_IDLE", disabled)

    def test_config_uses_initramfs_without_unused_block_stack(self) -> None:
        disabled = disabled_settings(self.fragment)
        for setting in (
            "CONFIG_BLOCK",
            "CONFIG_BLK_DEV_LOOP",
            "CONFIG_MTD",
            "CONFIG_MEDIA_SUPPORT",
            "CONFIG_VIRTIO_MENU",
        ):
            self.assertIn(setting, disabled)
        self.assertIn("KCONFIG_ALLCONFIG=", self.script)
        self.assertIn("allnoconfig", self.script)
        self.assertNotIn(" merge_config.sh", self.script)

    def test_config_keeps_p3_console_initrd_and_fpu(self) -> None:
        enabled = enabled_settings(self.fragment)
        for setting in (
            "CONFIG_FPU",
            "CONFIG_BLK_DEV_INITRD",
            "CONFIG_RD_GZIP",
            "CONFIG_DEVTMPFS",
            "CONFIG_SERIAL_EARLYCON",
            "CONFIG_SERIAL_8250",
            "CONFIG_SERIAL_8250_CONSOLE",
            "CONFIG_SERIAL_OF_PLATFORM",
            "CONFIG_RISCV_TIMER",
            "CONFIG_SIFIVE_PLIC",
        ):
            self.assertEqual(enabled[setting], "y")

    def test_no_reloc_patch_does_not_change_hsm(self) -> None:
        self.assertIn("P3_FIXED_FDT_NORELOC", self.patch)
        self.assertIn("beq\tzero, zero, _fdt_reloc_done", self.patch)
        self.assertNotIn("sbi_hsm.c", self.patch)
        self.assertNotIn("START_PENDING", self.patch)
        self.assertNotIn("P3_LINUX51_LEGACY_SMP", self.patch)

    def test_fixed_copy_layout_and_compressed_output_are_explicit(self) -> None:
        for address in ("0x80000000", "0x80200000", "0x81600000", "0x81700000"):
            self.assertIn(f'="{address}"', self.script)
        self.assertIn('gzip -9n -c "$sd_img"', self.script)
        self.assertIn("p3_make_build66_opensbi_flat_image.py", self.script)
        self.assertIn('"OpenSBI firmware"', self.script)
        self.assertIn('"Linux vmlinux"', self.script)
        self.assertIn("custom CSR 0x701", self.script)
        self.assertIn(
            "/root/XSBench -t 1 -s small -p 1000 -l 1",
            self.script,
        )


if __name__ == "__main__":
    unittest.main()
