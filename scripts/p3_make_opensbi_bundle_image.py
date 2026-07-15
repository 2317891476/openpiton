#!/usr/bin/env python3
import argparse
import struct
import subprocess
from pathlib import Path

from p3_platform_config import (
    DEFAULT_DEVICE_MAP,
    Region,
    int_arg,
    load_device_map,
    validate_load_layout,
)


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


def fdt_hex_cells(dtb: Path, node: str, prop: str) -> list[int]:
    try:
        result = subprocess.run(
            ["fdtget", "-tx", str(dtb), node, prop],
            check=True,
            text=True,
            capture_output=True,
        )
    except FileNotFoundError as exc:
        raise ValueError("fdtget is required to validate the bundle DTB") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise ValueError(f"cannot read DTB property {node}:{prop}: {detail}") from exc
    try:
        return [int(cell, 16) for cell in result.stdout.split()]
    except ValueError as exc:
        raise ValueError(f"DTB property {node}:{prop} is not a cell list") from exc


def cells_to_u64(cells: list[int], description: str) -> int:
    if len(cells) != 2:
        raise ValueError(f"{description} must contain two 32-bit cells")
    return (cells[0] << 32) | cells[1]


def validate_dtb_contract(
    dtb: Path, memory: Region, initrd_addr: int, initrd_size: int
) -> None:
    memory_cells = fdt_hex_cells(dtb, f"/memory@{memory.base:x}", "reg")
    if len(memory_cells) != 4:
        raise ValueError("DTB memory reg must contain four cells")
    dtb_memory_base = cells_to_u64(memory_cells[:2], "DTB memory base")
    dtb_memory_size = cells_to_u64(memory_cells[2:], "DTB memory size")
    if dtb_memory_base != memory.base or dtb_memory_size != memory.size:
        raise ValueError(
            "DTB memory range disagrees with the hardware device map: "
            f"DTB=[0x{dtb_memory_base:x},0x{dtb_memory_base + dtb_memory_size:x}) "
            f"hardware=[0x{memory.base:x},0x{memory.end:x})"
        )

    dtb_initrd_start = cells_to_u64(
        fdt_hex_cells(dtb, "/chosen", "linux,initrd-start"),
        "linux,initrd-start",
    )
    dtb_initrd_end = cells_to_u64(
        fdt_hex_cells(dtb, "/chosen", "linux,initrd-end"),
        "linux,initrd-end",
    )
    expected_initrd_end = initrd_addr + initrd_size
    if dtb_initrd_start != initrd_addr or dtb_initrd_end != expected_initrd_end:
        raise ValueError(
            "DTB initramfs range disagrees with the bundle component: "
            f"DTB=[0x{dtb_initrd_start:x},0x{dtb_initrd_end:x}) "
            f"bundle=[0x{initrd_addr:x},0x{expected_initrd_end:x})"
        )


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
    parser.add_argument("--device-map", type=Path, default=DEFAULT_DEVICE_MAP)
    parser.add_argument("--fw-addr", type=int_arg, default=0x80000000)
    parser.add_argument("--image-addr", type=int_arg, default=0x80200000)
    parser.add_argument("--dtb-addr", type=int_arg, default=0x88000000)
    parser.add_argument("--initrd-addr", type=int_arg, default=0x90000000)
    args = parser.parse_args()

    components = [
        (KIND_FW, Path(args.fw), args.fw_addr),
        (KIND_IMAGE, Path(args.image), args.image_addr),
        (KIND_DTB, Path(args.dtb), args.dtb_addr),
        (KIND_INITRD, Path(args.initrd), args.initrd_addr),
    ]

    for _, path, _ in components:
        if not path.is_file():
            raise SystemExit(f"missing input: {path}")

    try:
        memory = load_device_map(args.device_map, ("mem",))["mem"]
        validate_load_layout(
            [
                (path.name, load_addr, path.stat().st_size)
                for _kind, path, load_addr in components
            ],
            memory,
        )
        initrd_path = Path(args.initrd)
        validate_dtb_contract(
            Path(args.dtb),
            memory,
            args.initrd_addr,
            initrd_path.stat().st_size,
        )
    except (OSError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

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
        args.fw_addr,
        args.dtb_addr,
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
        f.write(f"device_map={args.device_map}\n")
        f.write(f"memory_base=0x{memory.base:x}\n")
        f.write(f"memory_size=0x{memory.size:x}\n")
        f.write(f"entry_addr=0x{args.fw_addr:x}\n")
        f.write(f"fdt_addr=0x{args.dtb_addr:x}\n")
        for (kind, _flags, offset_lba, size, load_addr, _reserved), (_, path, _) in zip(entries, components):
            f.write(
                f"component kind={kind} offset_lba={offset_lba} "
                f"size={size} load_addr=0x{load_addr:x} path={path}\n"
            )

    run(["sha256sum", str(out), str(manifest)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
