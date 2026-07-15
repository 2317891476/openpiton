#!/usr/bin/env python3
"""Validate a generated P3 OpenSBI/Linux DTB against the hardware map."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess

from p3_platform_config import DEFAULT_DEVICE_MAP, int_arg, load_device_map


REQUIRED_PORTS = ("mem", "sd", "uart", "ariane_clint", "ariane_plic")


def fdtget(dtb: Path, value_type: str, node: str, prop: str) -> str:
    try:
        result = subprocess.run(
            ["fdtget", f"-t{value_type}", str(dtb), node, prop],
            check=True,
            text=True,
            capture_output=True,
        )
    except FileNotFoundError as exc:
        raise ValueError("fdtget is required to validate the generated DTB") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise ValueError(f"cannot read DTB property {node}:{prop}: {detail}") from exc
    return result.stdout.strip()


def fdt_children(dtb: Path, node: str) -> list[str]:
    try:
        result = subprocess.run(
            ["fdtget", "-l", str(dtb), node],
            check=True,
            text=True,
            capture_output=True,
        )
    except FileNotFoundError as exc:
        raise ValueError("fdtget is required to validate the generated DTB") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise ValueError(f"cannot list DTB node {node}: {detail}") from exc
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def hex_cells(dtb: Path, node: str, prop: str) -> list[int]:
    raw = fdtget(dtb, "x", node, prop)
    try:
        return [int(cell, 16) for cell in raw.split()]
    except ValueError as exc:
        raise ValueError(f"DTB property {node}:{prop} is not a cell list: {raw}") from exc


def cells_to_u64(cells: list[int], description: str) -> int:
    if len(cells) != 2:
        raise ValueError(f"{description} must contain two 32-bit cells, got {cells}")
    return (cells[0] << 32) | cells[1]


def require_equal(actual, expected, description: str) -> None:
    if actual != expected:
        raise ValueError(
            f"{description} mismatch: expected {expected!r}, got {actual!r}"
        )


def require_reg(dtb: Path, node: str, base: int, size: int) -> None:
    cells = hex_cells(dtb, node, "reg")
    if len(cells) != 4:
        raise ValueError(f"{node}:reg must contain four cells, got {cells}")
    require_equal(cells_to_u64(cells[:2], f"{node} base"), base, f"{node} base")
    require_equal(cells_to_u64(cells[2:], f"{node} size"), size, f"{node} size")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a P3 OpenSBI/Linux DTB against devices_ariane.xml."
    )
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--device-map", type=Path, default=DEFAULT_DEVICE_MAP)
    parser.add_argument("--harts", type=int, required=True)
    parser.add_argument("--cpu-frequency", type=int_arg, default=30_000_000)
    parser.add_argument("--timebase-divisor", type=int_arg, default=128)
    parser.add_argument(
        "--timebase-frequency",
        type=int_arg,
        help="optional assertion; must equal cpu-frequency/timebase-divisor",
    )
    parser.add_argument("--plic-ndev", type=int_arg, default=2)
    parser.add_argument("--bootargs")
    parser.add_argument("--initrd", type=Path)
    parser.add_argument("--initrd-addr", type=int_arg, default=0x90000000)
    args = parser.parse_args()

    if not args.dtb.is_file():
        raise SystemExit(f"DTB does not exist: {args.dtb}")
    if args.harts < 1:
        raise SystemExit("--harts must be positive")
    if args.cpu_frequency < 1 or args.timebase_divisor < 1:
        raise SystemExit("CPU frequency and timebase divisor must be positive")
    if args.cpu_frequency % args.timebase_divisor:
        raise SystemExit(
            "--cpu-frequency must be exactly divisible by --timebase-divisor"
        )
    derived_timebase_frequency = args.cpu_frequency // args.timebase_divisor
    if (
        args.timebase_frequency is not None
        and args.timebase_frequency != derived_timebase_frequency
    ):
        raise SystemExit(
            "--timebase-frequency disagrees with cpu-frequency/timebase-divisor: "
            f"expected {derived_timebase_frequency}, got {args.timebase_frequency}"
        )
    timebase_frequency = derived_timebase_frequency
    if args.plic_ndev < 1:
        raise SystemExit("--plic-ndev must be positive")

    try:
        regions = load_device_map(args.device_map, REQUIRED_PORTS)
        memory = regions["mem"]
        memory_node = f"/memory@{memory.base:x}"
        require_reg(args.dtb, memory_node, memory.base, memory.size)

        peripheral_nodes = {
            "sd": f"/sdhci@{regions['sd'].base:x}",
            "uart": f"/uart@{regions['uart'].base:x}",
            "ariane_clint": f"/clint@{regions['ariane_clint'].base:x}",
            "ariane_plic": f"/plic@{regions['ariane_plic'].base:x}",
        }
        for name, node in peripheral_nodes.items():
            region = regions[name]
            require_reg(args.dtb, node, region.base, region.size)

        require_equal(
            hex_cells(args.dtb, "/cpus", "timebase-frequency"),
            [timebase_frequency],
            "timebase-frequency",
        )
        expected_cpu_nodes = {f"cpu@{idx}" for idx in range(args.harts)}
        actual_cpu_nodes = {
            node for node in fdt_children(args.dtb, "/cpus") if node.startswith("cpu@")
        }
        require_equal(actual_cpu_nodes, expected_cpu_nodes, "CPU node set")
        for idx in range(args.harts):
            node = f"/cpus/cpu@{idx}"
            require_equal(hex_cells(args.dtb, node, "reg"), [idx], f"{node}:reg")
            require_equal(
                hex_cells(args.dtb, node, "clock-frequency"),
                [args.cpu_frequency],
                f"{node}:clock-frequency",
            )

        require_equal(
            len(
                hex_cells(
                    args.dtb,
                    peripheral_nodes["ariane_clint"],
                    "interrupts-extended",
                )
            ),
            args.harts * 4,
            "CLINT interrupts-extended cell count",
        )
        require_equal(
            len(
                hex_cells(
                    args.dtb,
                    peripheral_nodes["ariane_plic"],
                    "interrupts-extended",
                )
            ),
            args.harts * 4,
            "PLIC interrupts-extended cell count",
        )
        require_equal(
            hex_cells(
                args.dtb, peripheral_nodes["ariane_plic"], "riscv,ndev"
            ),
            [args.plic_ndev],
            "PLIC riscv,ndev",
        )

        if args.bootargs is not None:
            require_equal(
                fdtget(args.dtb, "s", "/chosen", "bootargs"),
                args.bootargs,
                "bootargs",
            )

        if args.initrd is not None:
            if not args.initrd.is_file():
                raise ValueError(f"initramfs does not exist: {args.initrd}")
            initrd_size = args.initrd.stat().st_size
            if not memory.contains(args.initrd_addr, initrd_size):
                raise ValueError(
                    f"initramfs range [0x{args.initrd_addr:x},"
                    f"0x{args.initrd_addr + initrd_size:x}) is outside DDR "
                    f"[0x{memory.base:x},0x{memory.end:x})"
                )
            require_equal(
                cells_to_u64(
                    hex_cells(args.dtb, "/chosen", "linux,initrd-start"),
                    "linux,initrd-start",
                ),
                args.initrd_addr,
                "linux,initrd-start",
            )
            require_equal(
                cells_to_u64(
                    hex_cells(args.dtb, "/chosen", "linux,initrd-end"),
                    "linux,initrd-end",
                ),
                args.initrd_addr + initrd_size,
                "linux,initrd-end",
            )
    except ValueError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    print(
        "P3 DTB validation passed: "
        f"harts={args.harts} memory=[0x{memory.base:x},0x{memory.end:x}) "
        f"timebase={timebase_frequency}Hz"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
