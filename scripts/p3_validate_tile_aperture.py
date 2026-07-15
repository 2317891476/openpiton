#!/usr/bin/env python3
"""Reject generated CVA6 memory apertures that disagree with the P3 map."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

from p3_platform_config import DEFAULT_DEVICE_MAP, load_device_map


def parameter_values(text: str, name: str) -> list[int]:
    match = re.search(
        rf"\.{re.escape(name)}\s*\(\s*(\{{.*?\}})\s*\)",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValueError(f"generated tile RTL lacks parameter {name}")
    values = [int(value, 16) for value in re.findall(r"64'h([0-9a-fA-F]+)", match.group(1))]
    if not values:
        raise ValueError(f"generated tile RTL parameter {name} has no 64-bit values")
    return values


def require_region(
    bases: list[int], lengths: list[int], expected_base: int, expected_size: int, name: str
) -> None:
    if len(bases) != len(lengths):
        raise ValueError(
            f"{name} base/length count mismatch: {len(bases)} vs {len(lengths)}"
        )
    matches = [length for base, length in zip(bases, lengths) if base == expected_base]
    if not matches:
        raise ValueError(f"{name} has no DDR rule at 0x{expected_base:x}")
    if matches != [expected_size]:
        rendered = ", ".join(f"0x{value:x}" for value in matches)
        raise ValueError(
            f"{name} DDR length mismatch at 0x{expected_base:x}: "
            f"expected 0x{expected_size:x}, got {rendered}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate generated tile.tmp.v CVA6 apertures against the P3 map."
    )
    parser.add_argument("--tile-rtl", required=True, type=Path)
    parser.add_argument("--device-map", type=Path, default=DEFAULT_DEVICE_MAP)
    args = parser.parse_args()

    if not args.tile_rtl.is_file():
        raise SystemExit(f"generated tile RTL does not exist: {args.tile_rtl}")

    try:
        memory = load_device_map(args.device_map, ("mem",))["mem"]
        text = args.tile_rtl.read_text(encoding="utf-8")
        require_region(
            parameter_values(text, "ExecuteRegionAddrBase"),
            parameter_values(text, "ExecuteRegionLength"),
            memory.base,
            memory.size,
            "CVA6 execute aperture",
        )
        require_region(
            parameter_values(text, "CachedRegionAddrBase"),
            parameter_values(text, "CachedRegionLength"),
            memory.base,
            memory.size,
            "CVA6 cacheable aperture",
        )
    except (OSError, UnicodeError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    print(
        "P3 CVA6 aperture validation passed: "
        f"DDR=[0x{memory.base:x},0x{memory.end:x}) tile={args.tile_rtl}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
