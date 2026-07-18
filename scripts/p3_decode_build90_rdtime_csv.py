#!/usr/bin/env python3
"""Decode the Build 90 clean-RTL TIME/commit ILA capture."""

import argparse
import csv
import pathlib
import re
import sys


TARGET_PC = 0xFFFFFFFF807D8A9E


def hex_value(text: str) -> int:
    return int(text, 16) if text else 0


def field_width(header: str) -> int:
    match = re.search(r"\[(\d+):(\d+)\]$", header)
    if not match:
        return 1
    return abs(int(match.group(1)) - int(match.group(2))) + 1


def assemble_probe(row: list[str], headers: list[str], columns: list[int]) -> int:
    value = 0
    offset = 0
    for column in columns:
        value |= hex_value(row[column]) << offset
        offset += field_width(headers[column])
    return value


def require_one(headers: list[str], predicate, label: str) -> int:
    matches = [index for index, header in enumerate(headers) if predicate(header)]
    if len(matches) != 1:
        raise ValueError(f"expected one {label} column, found {len(matches)}")
    return matches[0]


def decode(path: pathlib.Path) -> dict[str, object]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        headers = next(reader)
        next(reader)  # Vivado radix row
        rows = list(reader)

    trigger_col = require_one(headers, lambda h: h == "TRIGGER", "trigger")
    pc_col = require_one(headers, lambda h: "[pc][63:0]" in h, "commit PC")
    valid_col = require_one(headers, lambda h: "[valid]" in h, "commit valid")
    ack_col = require_one(headers, lambda h: "commit_ack" in h, "commit ack")
    illegal_col = require_one(
        headers, lambda h: "csr_exception_csr_commit[cause]" in h, "CSR illegal"
    )
    priv_col = require_one(headers, lambda h: "priv_lvl_q_reg" in h, "privilege")
    addr_cols = [i for i, h in enumerate(headers) if "csr_addr_ex_csr" in h]
    mcounteren_cols = [i for i, h in enumerate(headers) if "mcounteren" in h]
    cycle_cols = [
        i
        for i, h in enumerate(headers)
        if "csr_regfile_i/" in h
        and "mcounteren" not in h
        and "priv_lvl" not in h
        and ("/Q" in h or "/cycle_q" in h)
    ]
    for columns, label in (
        (addr_cols, "CSR address"),
        (mcounteren_cols, "mcounteren"),
        (cycle_cols, "cycle"),
    ):
        if not columns:
            raise ValueError(f"no {label} columns found")

    decoded = []
    for index, row in enumerate(rows):
        decoded.append(
            {
                "index": index,
                "trigger": bool(int(row[trigger_col], 10)),
                "pc": hex_value(row[pc_col]),
                "valid": bool(hex_value(row[valid_col])),
                "ack": bool(hex_value(row[ack_col])),
                "csr": assemble_probe(row, headers, addr_cols),
                "illegal": bool(hex_value(row[illegal_col])),
                "priv": hex_value(row[priv_col]),
                "mcounteren": assemble_probe(row, headers, mcounteren_cols),
                "cycle": assemble_probe(row, headers, cycle_cols),
            }
        )

    target_samples = [row for row in decoded if row["pc"] == TARGET_PC]
    target_commits = [row for row in target_samples if row["valid"] and row["ack"]]
    clean_commits = [
        row
        for row in target_commits
        if row["csr"] == 0xC01
        and not row["illegal"]
        and row["priv"] == 1
        and row["mcounteren"] & 0x2
    ]
    cycles = [int(row["cycle"]) for row in decoded]
    verdict = bool(clean_commits and cycles and max(cycles) > min(cycles))
    return {
        "samples": len(decoded),
        "trigger_indices": [row["index"] for row in decoded if row["trigger"]],
        "distinct_pcs": len({row["pc"] for row in decoded}),
        "target_samples": len(target_samples),
        "target_commits": len(target_commits),
        "clean_commits": clean_commits,
        "illegal_samples": sum(bool(row["illegal"]) for row in decoded),
        "cycle_min": min(cycles) if cycles else 0,
        "cycle_max": max(cycles) if cycles else 0,
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = decode(args.csv)
    except (OSError, StopIteration, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print(f"samples={result['samples']}")
    print(f"trigger_indices={result['trigger_indices']}")
    print(f"distinct_pcs={result['distinct_pcs']}")
    print(f"target_pc=0x{TARGET_PC:016x}")
    print(f"target_samples={result['target_samples']}")
    print(f"target_commits={result['target_commits']}")
    print(f"illegal_samples={result['illegal_samples']}")
    print(
        f"cycle_range=0x{result['cycle_min']:016x}..0x{result['cycle_max']:016x}"
    )
    for row in result["clean_commits"][:4]:
        print(
            "clean_commit "
            f"sample={row['index']} csr=0x{row['csr']:03x} "
            f"priv={row['priv']} mcounteren=0x{row['mcounteren']:02x} "
            f"cycle=0x{row['cycle']:016x}"
        )
    if result["verdict"]:
        print("VERDICT: RDTIME_RETIRED_IN_LINUX_WINDOW")
        return 0
    print("VERDICT: RDTIME_NOT_PROVEN")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
