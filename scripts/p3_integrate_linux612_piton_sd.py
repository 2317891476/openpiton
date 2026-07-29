#!/usr/bin/env python3
"""Integrate the P3 SD block driver into an extracted Linux 6.12 tree."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil


KCONFIG_MARKER = "if BLK_DEV\n"
KCONFIG_ENTRY = """
config OPENPITON_ARIANE_SD
\tbool "OpenPiton+Ariane FPGA SD block device"
\tdepends on RISCV
\thelp
\t  Expose the OpenPiton FPGA SD transaction-manager aperture as a
\t  partitionable Linux block device named /dev/piton_sd.

"""
MAKEFILE_MARKER = "obj-$(CONFIG_SUNVDC)\t\t+= sunvdc.o\n"
MAKEFILE_ENTRY = "obj-$(CONFIG_OPENPITON_ARIANE_SD) += piton_sd.o\n"


def insert_once(path: Path, marker: str, entry: str, token: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(token)
    if count == 1:
        return
    if count:
        raise RuntimeError(f"{path}: expected at most one {token!r}, got {count}")
    if text.count(marker) != 1:
        raise RuntimeError(f"{path}: integration marker is missing or ambiguous")
    path.write_text(text.replace(marker, marker + entry, 1), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-dir", required=True, type=Path)
    parser.add_argument("--driver", required=True, type=Path)
    args = parser.parse_args()

    linux_dir = args.linux_dir.resolve()
    driver = args.driver.resolve()
    kconfig = linux_dir / "drivers/block/Kconfig"
    makefile = linux_dir / "drivers/block/Makefile"
    destination = linux_dir / "drivers/block/piton_sd.c"

    for path in (linux_dir / "Makefile", kconfig, makefile, driver):
        if not path.is_file():
            raise SystemExit(f"ERROR: missing required file: {path}")

    shutil.copyfile(driver, destination)
    insert_once(kconfig, KCONFIG_MARKER, KCONFIG_ENTRY, "config OPENPITON_ARIANE_SD")
    insert_once(
        makefile,
        MAKEFILE_MARKER,
        MAKEFILE_ENTRY,
        "obj-$(CONFIG_OPENPITON_ARIANE_SD)",
    )

    if destination.read_bytes() != driver.read_bytes():
        raise RuntimeError("driver copy verification failed")
    print(f"Integrated Linux 6.12 P3 SD driver: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
