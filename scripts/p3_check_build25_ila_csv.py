#!/usr/bin/env python3
"""Check Build 25 minimal ILA CSV for clock/debug activity."""

import csv
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: scripts/p3_check_build25_ila_csv.py <ila_capture_build25_minimal.csv>")
        return 2

    path = Path(sys.argv[1])
    rows = list(csv.DictReader(path.open(newline="")))
    rows = [row for row in rows if not row.get("Sample in Buffer", "").startswith("Radix")]
    if not rows:
        print("ERROR: no sample rows found")
        return 1

    ignored_cols = {"Sample in Buffer", "Trigger"}
    data_cols = [col for col in rows[0] if col not in ignored_cols]
    heartbeat_cols = [
        col for col in data_cols
        if "p3_min_dbg_heartbeat" in col
        or any(f"probe{idx}" in col for idx in (0, 1, 2, 3, 11))
    ]
    if not heartbeat_cols:
        heartbeat_cols = data_cols

    print(f"samples={len(rows)}")
    for col in data_cols:
        values = [row[col] for row in rows]
        unique = sorted(set(values))
        print(f"column={col} unique_count={len(unique)} first={values[0]} last={values[-1]}")

    toggling_heartbeat_cols = []
    for col in heartbeat_cols:
        values = [row[col] for row in rows]
        if len(set(values)) > 1:
            toggling_heartbeat_cols.append(col)

    if not toggling_heartbeat_cols:
        print("ERROR: no heartbeat/debug activity changed across the capture")
        return 1

    print(f"PASS: activity changed on {toggling_heartbeat_cols}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
