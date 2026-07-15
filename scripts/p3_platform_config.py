#!/usr/bin/env python3
"""Shared P3 platform-map parsing and address-range validation helpers."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DEVICE_MAP = (
    REPO_ROOT / "piton/design/xilinx/huaprop3/devices_ariane.xml"
)


@dataclass(frozen=True)
class Region:
    name: str
    base: int
    size: int

    @property
    def end(self) -> int:
        return self.base + self.size

    def contains(self, base: int, size: int) -> bool:
        return size > 0 and self.base <= base and base + size <= self.end


def int_arg(value: str) -> int:
    """Parse a decimal or 0x-prefixed command-line integer."""

    try:
        parsed = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid integer: {value}") from exc
    if parsed < 0:
        raise argparse.ArgumentTypeError(f"integer must be non-negative: {value}")
    return parsed


def load_device_map(path: Path, required: tuple[str, ...] = ()) -> dict[str, Region]:
    """Load addressable ports from an OpenPiton devices XML file."""

    if not path.is_file():
        raise ValueError(f"device map does not exist: {path}")

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        raise ValueError(f"invalid device map XML {path}: {exc}") from exc

    regions: dict[str, Region] = {}
    for port in root.findall("port"):
        name_node = port.find("name")
        if name_node is None or not name_node.text:
            raise ValueError(f"device map {path} has a port without a name")
        name = name_node.text.strip()
        base_node = port.find("base")
        size_node = port.find("length")
        if base_node is None and size_node is None:
            continue
        if (
            base_node is None
            or size_node is None
            or not base_node.text
            or not size_node.text
        ):
            raise ValueError(f"device-map port {name} lacks base or length")
        if name in regions:
            raise ValueError(f"duplicate device-map port: {name}")
        try:
            base = int(base_node.text.strip(), 0)
            size = int(size_node.text.strip(), 0)
        except ValueError as exc:
            raise ValueError(f"device-map port {name} has an invalid range") from exc
        if base < 0 or size <= 0 or base + size > 1 << 64:
            raise ValueError(
                f"device-map port {name} has an invalid 64-bit range: "
                f"base=0x{base:x} size=0x{size:x}"
            )
        regions[name] = Region(name=name, base=base, size=size)

    missing = [name for name in required if name not in regions]
    if missing:
        raise ValueError(
            f"device map {path} lacks required ports: {', '.join(missing)}"
        )
    return regions


def u64_cells(value: int) -> tuple[int, int]:
    if value < 0 or value >= 1 << 64:
        raise ValueError(f"value is outside the unsigned 64-bit range: {value}")
    return value >> 32, value & 0xFFFFFFFF


def format_u64_cells(value: int) -> str:
    high, low = u64_cells(value)
    return f"0x{high:08x} 0x{low:08x}"


def validate_load_layout(
    components: list[tuple[str, int, int]], memory: Region
) -> None:
    """Require non-empty, non-overlapping component ranges inside DDR."""

    ordered = sorted(components, key=lambda component: component[1])
    for name, base, size in ordered:
        if size <= 0:
            raise ValueError(f"component {name} is empty")
        if base < 0 or base + size > 1 << 64:
            raise ValueError(
                f"component {name} has an invalid 64-bit range: "
                f"base=0x{base:x} size=0x{size:x}"
            )
        if not memory.contains(base, size):
            raise ValueError(
                f"component {name} range [0x{base:x},0x{base + size:x}) is "
                f"outside DDR [0x{memory.base:x},0x{memory.end:x})"
            )

    for left, right in zip(ordered, ordered[1:]):
        left_name, left_base, left_size = left
        right_name, right_base, _right_size = right
        if left_base + left_size > right_base:
            raise ValueError(
                f"component ranges overlap: {left_name} "
                f"[0x{left_base:x},0x{left_base + left_size:x}) and "
                f"{right_name} starting at 0x{right_base:x}"
            )
