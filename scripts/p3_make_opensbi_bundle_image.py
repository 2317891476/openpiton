#!/usr/bin/env python3
import argparse
import os
import struct
import subprocess
from pathlib import Path


MAGIC0 = 0x534F3350
MAGIC1 = 0x34364942
VERSION = 1
HEADER_SIZE = 512
KIND_FW = 1
KIND_IMAGE = 2
KIND_DTB = 3
KIND_INITRD = 4


def ceil512(value: int) -> int:
    return (value + 511) // 512


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def run_input(cmd: list[str], data: str) -> None:
    subprocess.run(cmd, input=data, text=True, check=True)


def write_aligned(dst, src_path: Path) -> int:
    data = src_path.read_bytes()
    dst.write(data)
    pad = (-len(data)) % 512
    if pad:
        dst.write(b"\0" * pad)
    return len(data)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a GPT SD image containing a P3 OpenSBI boot bundle."
    )
    parser.add_argument("--fw", required=True, help="OpenSBI fw_jump binary")
    parser.add_argument("--image", required=True, help="Linux Image")
    parser.add_argument("--dtb", required=True, help="P3 DTB")
    parser.add_argument("--initrd", required=True, help="initramfs cpio.gz")
    parser.add_argument("--out", required=True)
    parser.add_argument("--size-mib", type=int, default=256)
    parser.add_argument("--partition-start-lba", type=int, default=2048)
    parser.add_argument("--fw-addr", default="0x80000000")
    parser.add_argument("--image-addr", default="0x80200000")
    parser.add_argument("--dtb-addr", default="0x88000000")
    parser.add_argument("--initrd-addr", default="0x90000000")
    args = parser.parse_args()

    components = [
        (KIND_FW, Path(args.fw), int(args.fw_addr, 0)),
        (KIND_IMAGE, Path(args.image), int(args.image_addr, 0)),
        (KIND_DTB, Path(args.dtb), int(args.dtb_addr, 0)),
        (KIND_INITRD, Path(args.initrd), int(args.initrd_addr, 0)),
    ]

    for _, path, _ in components:
        if not path.is_file():
            raise SystemExit(f"missing input: {path}")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    size_bytes = args.size_mib * 1024 * 1024

    with out.open("wb") as f:
        f.truncate(size_bytes)

    layout = (
        "label: gpt\n"
        "unit: sectors\n"
        f"first-lba: {args.partition_start_lba}\n"
        "\n"
        f"start={args.partition_start_lba}, type=linux\n"
    )
    run_input(["sfdisk", str(out)], layout)

    header_base = args.partition_start_lba * 512
    cursor_lba = 1
    entries = []
    payloads = []
    for kind, path, load_addr in components:
        size = path.stat().st_size
        entries.append((kind, 0, cursor_lba, size, load_addr, 0))
        payloads.append((cursor_lba, path))
        cursor_lba += ceil512(size)

    used_bytes = header_base + cursor_lba * 512
    if used_bytes > size_bytes:
        raise SystemExit(
            f"bundle uses {used_bytes} bytes, larger than image size {size_bytes}"
        )

    header = bytearray(HEADER_SIZE)
    struct.pack_into(
        "<6I6Q",
        header,
        0,
        MAGIC0,
        MAGIC1,
        VERSION,
        HEADER_SIZE,
        len(entries),
        0,
        int(args.fw_addr, 0),
        int(args.dtb_addr, 0),
        0,
        0,
        0,
        0,
    )
    offset = struct.calcsize("<6I6Q")
    for entry in entries:
        struct.pack_into("<IIQQQQ", header, offset, *entry)
        offset += struct.calcsize("<IIQQQQ")

    with out.open("r+b") as f:
        f.seek(header_base)
        f.write(header)
        for offset_lba, path in payloads:
            f.seek(header_base + offset_lba * 512)
            write_aligned(f, path)

    manifest = out.with_suffix(out.suffix + ".manifest")
    with manifest.open("w", encoding="ascii") as f:
        f.write(f"image={out}\n")
        f.write(f"size_bytes={size_bytes}\n")
        f.write(f"partition_start_lba={args.partition_start_lba}\n")
        f.write(f"entry_addr={args.fw_addr}\n")
        f.write(f"fdt_addr={args.dtb_addr}\n")
        for (kind, _flags, offset_lba, size, load_addr, _reserved), (_, path, _) in zip(entries, components):
            f.write(
                f"component kind={kind} offset_lba={offset_lba} "
                f"size={size} load_addr=0x{load_addr:x} path={path}\n"
            )

    run(["sha256sum", str(out), str(manifest)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
