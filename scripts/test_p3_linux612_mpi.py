#!/usr/bin/env python3
"""Static contract tests for the P3 Linux 6.12 MPI-ready system profile."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent


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


class P3Linux612MpiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = (SCRIPT_DIR / "p3_linux612_build66_mpi.config").read_text()
        cls.build = (
            SCRIPT_DIR / "p3_prepare_build66_1hart_linux612_image.sh"
        ).read_text()
        cls.wrapper = (
            SCRIPT_DIR / "p3_prepare_build66_1hart_linux612_mpi_image.sh"
        ).read_text()
        cls.driver = (SCRIPT_DIR / "p3_linux612_piton_sd.c").read_text()
        cls.integrator = (
            SCRIPT_DIR / "p3_integrate_linux612_piton_sd.py"
        ).read_text()
        cls.init = (SCRIPT_DIR / "p3_linux612_mpi_init.sh").read_text()
        cls.smoke = (
            SCRIPT_DIR / "p3_linux612_mpi_system_smoke.c"
        ).read_text()

    def test_kernel_is_one_image_for_single_to_64_harts(self) -> None:
        enabled = enabled_settings(self.config)
        self.assertEqual(enabled["CONFIG_SMP"], "y")
        self.assertEqual(enabled["CONFIG_NR_CPUS"], "64")
        self.assertEqual(enabled["CONFIG_RISCV_SBI"], "y")
        self.assertIn("CONFIG_RISCV_SBI_V01", disabled_settings(self.config))
        self.assertIn("--harts 1", self.build)

    def test_mpi_and_openmp_system_primitives_are_enabled(self) -> None:
        enabled = enabled_settings(self.config)
        for setting in (
            "CONFIG_FPU",
            "CONFIG_BINFMT_SCRIPT",
            "CONFIG_FUTEX",
            "CONFIG_SYSVIPC",
            "CONFIG_POSIX_MQUEUE",
            "CONFIG_CROSS_MEMORY_ATTACH",
            "CONFIG_SHMEM",
            "CONFIG_AIO",
            "CONFIG_ADVISE_SYSCALLS",
            "CONFIG_MEMBARRIER",
            "CONFIG_RSEQ",
            "CONFIG_NET",
            "CONFIG_PACKET",
            "CONFIG_UNIX",
            "CONFIG_INET",
        ):
            self.assertEqual(enabled[setting], "y", setting)

    def test_targeted_storage_is_enabled_without_loop_driver(self) -> None:
        enabled = enabled_settings(self.config)
        disabled = disabled_settings(self.config)
        for setting in (
            "CONFIG_BLOCK",
            "CONFIG_BLK_DEV",
            "CONFIG_OPENPITON_ARIANE_SD",
            "CONFIG_MSDOS_PARTITION",
            "CONFIG_EFI_PARTITION",
            "CONFIG_EXT4_FS",
        ):
            self.assertEqual(enabled[setting], "y", setting)
        for setting in (
            "CONFIG_BLK_DEV_LOOP",
            "CONFIG_MTD",
            "CONFIG_MEDIA_SUPPORT",
            "CONFIG_VIRTIO_MENU",
        ):
            self.assertIn(setting, disabled)

    def test_driver_uses_linux612_api_and_serializes_multihart_io(self) -> None:
        driver_body = self.driver.split("*/", 1)[1]
        for obsolete in (
            "blk_alloc_queue",
            "blk_queue_make_request",
            "blk_cleanup_queue",
        ):
            self.assertNotIn(obsolete, driver_body)
        self.assertNotRegex(driver_body, r"\balloc_disk\(")
        for modern in (
            "blk_alloc_disk",
            ".submit_bio = piton_sd_submit_bio",
            "DEFINE_SPINLOCK(piton_sd_lock)",
            "spin_lock_irqsave",
            "REQ_OP_READ",
            "REQ_OP_WRITE",
            "PITON_SD_GPT_SIGNATURE",
        ):
            self.assertIn(modern, self.driver)

    def test_driver_integration_is_idempotent_and_profile_gated(self) -> None:
        self.assertIn("insert_once", self.integrator)
        self.assertIn("config OPENPITON_ARIANE_SD", self.integrator)
        self.assertIn('[[ "$profile" == "mpi" ]]', self.build)
        self.assertIn("p3_integrate_linux612_piton_sd.py", self.build)
        self.assertIn("CONFIG_OPENPITON_ARIANE_SD=y", self.build)
        self.assertIn("P3_LINUX612_PROFILE=mpi", self.wrapper)

    def test_initramfs_runs_system_smoke_before_shell(self) -> None:
        self.assertIn("mount -t tmpfs tmpfs /dev/shm", self.init)
        self.assertIn("mount -t mqueue mqueue /dev/mqueue", self.init)
        self.assertIn("ip link set lo up", self.init)
        self.assertLess(
            self.init.index("/usr/bin/p3_mpi_system_smoke"),
            self.init.index("exec /bin/sh"),
        )
        for marker in (
            "pthread_futex",
            "shared_mmap_fork",
            "posix_mqueue",
            "unix_socket",
            "tcp_loopback",
            "cpu_affinity",
            "clock_monotonic",
            "P3_MPI_SYS ALL_PASS",
        ):
            self.assertIn(marker, self.smoke)

    def test_transport_remains_compressed_and_hash_asserted(self) -> None:
        self.assertIn("P3_LINUX612_INITRD_SHA256", self.build)
        self.assertIn('gzip -9n -c "$sd_img"', self.build)
        self.assertIn('"$sd_img.gz"', self.build)


if __name__ == "__main__":
    unittest.main()
