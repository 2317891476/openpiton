#!/usr/bin/env python3
"""Pack OpenSBI/Linux for the validated Build 66 fixed-window bootrom."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import subprocess

from p3_make_opensbi_bundle_image import validate_dtb_contract
from p3_platform_config import (
    DEFAULT_DEVICE_MAP,
    Region,
    int_arg,
    load_device_map,
    validate_load_layout,
)


def run_input(cmd: list[str], data: str) -> None:
    subprocess.run(cmd, input=data, text=True, check=True)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_file_at(dst, src_path: Path, offset: int) -> None:
    dst.seek(offset)
    with src_path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            dst.write(chunk)


def read_sha256(path: Path, offset: int, size: int) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as src:
        src.seek(offset)
        remaining = size
        while remaining:
            chunk = src.read(min(1024 * 1024, remaining))
            if not chunk:
                raise ValueError(
                    f"short image read at offset {offset}: {remaining} bytes missing"
                )
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def validate_copy_window(
    components: list[tuple[str, int, int]], window: Region
) -> None:
    for name, base, size in components:
        if not window.contains(base, size):
            raise ValueError(
                f"component {name} range [0x{base:x},0x{base + size:x}) is "
                f"outside the Build 66 copy window "
                f"[0x{window.base:x},0x{window.end:x})"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create a GPT image whose first partition is the fixed 32 MiB "
            "OpenSBI/Linux payload expected by the validated Build 66 bootrom."
        )
    )
    parser.add_argument("--fw", required=True, type=Path)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--initrd", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--size-mib", type=int_arg, default=256)
    parser.add_argument("--partition-start-lba", type=int_arg, default=2048)
    parser.add_argument("--copy-size-mib", type=int_arg, default=32)
    parser.add_argument("--device-map", type=Path, default=DEFAULT_DEVICE_MAP)
    parser.add_argument("--load-base", type=int_arg, default=0x80000000)
    parser.add_argument("--fw-addr", type=int_arg, default=0x80000000)
    parser.add_argument("--image-addr", type=int_arg, default=0x80200000)
    parser.add_argument("--dtb-addr", type=int_arg, default=0x81600000)
    parser.add_argument("--initrd-addr", type=int_arg, default=0x81700000)
    args = parser.parse_args()

    paths = {
        "fw": args.fw,
        "image": args.image,
        "dtb": args.dtb,
        "initrd": args.initrd,
    }
    addresses = {
        "fw": args.fw_addr,
        "image": args.image_addr,
        "dtb": args.dtb_addr,
        "initrd": args.initrd_addr,
    }
    for name, path in paths.items():
        if not path.is_file():
            raise SystemExit(f"missing {name} input: {path}")

    if args.size_mib < 1 or args.copy_size_mib < 1:
        raise SystemExit("--size-mib and --copy-size-mib must be positive")
    if args.fw_addr != args.load_base:
        raise SystemExit(
            "ERROR: Build 66 jumps to the load base, so --fw-addr must equal "
            "--load-base"
        )

    components = [
        (name, addresses[name], path.stat().st_size)
        for name, path in paths.items()
    ]
    copy_size = args.copy_size_mib * 1024 * 1024
    copy_window = Region("build66-copy-window", args.load_base, copy_size)
    try:
        memory = load_device_map(args.device_map, ("mem",))["mem"]
        validate_load_layout(components, memory)
        validate_copy_window(components, copy_window)
        validate_dtb_contract(
            args.dtb,
            memory,
            args.initrd_addr,
            args.initrd.stat().st_size,
        )
    except (OSError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    size_bytes = args.size_mib * 1024 * 1024
    partition_offset = args.partition_start_lba * 512
    if partition_offset + copy_size > size_bytes:
        raise SystemExit(
            "ERROR: disk image is too small for the partition offset and Build 66 "
            "copy window"
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("wb") as dst:
        dst.truncate(size_bytes)

    layout = (
        "label: gpt\n"
        "unit: sectors\n"
        f"first-lba: {args.partition_start_lba}\n"
        "\n"
        f"start={args.partition_start_lba}, type=linux\n"
    )
    run_input(["sfdisk", str(args.out)], layout)

    with args.out.open("r+b") as dst:
        for name, path in paths.items():
            image_offset = partition_offset + addresses[name] - args.load_base
            copy_file_at(dst, path, image_offset)

    hashes: dict[str, str] = {}
    for name, path in paths.items():
        expected = file_sha256(path)
        image_offset = partition_offset + addresses[name] - args.load_base
        actual = read_sha256(args.out, image_offset, path.stat().st_size)
        if actual != expected:
            raise SystemExit(
                f"ERROR: packed {name} readback mismatch: {actual} != {expected}"
            )
        hashes[name] = expected
        print(
            f"verified {name}: addr=0x{addresses[name]:x} "
            f"size={path.stat().st_size} sha256={expected}"
        )

    manifest = args.out.with_suffix(args.out.suffix + ".manifest")
    with manifest.open("w", encoding="ascii") as dst:
        dst.write(f"image={args.out}\n")
        dst.write(f"size_bytes={size_bytes}\n")
        dst.write(f"partition_start_lba={args.partition_start_lba}\n")
        dst.write(f"copy_blocks={copy_size // 512}\n")
        dst.write(f"load_base=0x{args.load_base:x}\n")
        dst.write(f"copy_size=0x{copy_size:x}\n")
        dst.write(f"device_map={args.device_map}\n")
        dst.write(f"memory_base=0x{memory.base:x}\n")
        dst.write(f"memory_size=0x{memory.size:x}\n")
        for name, path in paths.items():
            dst.write(
                f"component name={name} load_addr=0x{addresses[name]:x} "
                f"offset=0x{addresses[name] - args.load_base:x} "
                f"size={path.stat().st_size} sha256={hashes[name]} path={path}\n"
            )

    print(f"image_sha256={file_sha256(args.out)}")
    print(f"manifest={manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
