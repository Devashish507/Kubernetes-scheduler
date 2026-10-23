#!/usr/bin/env python3
"""
scripts/compute_deltas.py
Week 7 – Compute percent-change deltas of energy-aware vs default scheduler.

Reads:  results/week6/summary.csv
Writes: results/week7/deltas.csv

For each scenario the script computes:
  delta_pct = (ea_value - default_value) / abs(default_value) * 100

A negative delta means the energy-aware scheduler used LESS of that metric
(good for power; may be good or bad for latency depending on context).

Columns in deltas.csv:
  scenario
  metric
  default_value
  ea_value
  abs_change
  delta_pct          (percent change, 2 decimal places)
  ea_std             (std dev of the ea metric, from summary.csv)
  default_std
  larger_than_std    (True if |abs_change| > max(ea_std, default_std))

Usage:
  python3 scripts/compute_deltas.py

Do NOT add unit tests.
"""

import csv
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SUMMARY_CSV = BASE_DIR / "results" / "week6" / "summary.csv"
OUT_DIR = BASE_DIR / "results" / "week7"
DELTAS_CSV = OUT_DIR / "deltas.csv"

# Metric pairs: (mean column, std column, human label)
METRICS = [
    ("mean_total_power_W",       "std_total_power_W",       "total_estimated_power_W"),
    ("mean_scheduling_delay_s",  "std_scheduling_delay_s",  "scheduling_delay_s"),
    ("mean_p95_latency_ms",      "std_p95_latency_ms",      "p95_latency_ms"),
    ("mean_util_spread_pct",     "std_util_spread_pct",     "util_spread_pct"),
]

SCENARIOS = ["scenario1", "scenario2", "scenario3", "scenario4"]


def _float(val):
    """Convert to float; return None if empty or non-numeric."""
    if val is None or str(val).strip() == "":
        return None
    try:
        return float(val)
    except ValueError:
        return None


def load_summary(path: Path) -> dict:
    """Return {(scenario, scheduler): row_dict}."""
    data = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            key = (row["scenario"], row["scheduler"])
            data[key] = row
    return data


def compute_deltas(data: dict) -> list[dict]:
    rows = []
    for scen in SCENARIOS:
        def_row = data.get((scen, "default"))
        ea_row  = data.get((scen, "energy-aware"))
        if def_row is None or ea_row is None:
            print(f"  WARNING: missing data for {scen} — skipping.")
            continue

        for mean_col, std_col, label in METRICS:
            def_val = _float(def_row.get(mean_col))
            ea_val  = _float(ea_row.get(mean_col))
            def_std = _float(def_row.get(std_col))
            ea_std  = _float(ea_row.get(std_col))

            if def_val is None or ea_val is None:
                # p95 is only present for scenario4; skip silently for others.
                continue

            abs_change = ea_val - def_val

            if def_val == 0.0:
                delta_pct = None
            else:
                delta_pct = (abs_change / abs(def_val)) * 100.0

            # Is the absolute change larger than the larger of the two std devs?
            max_std = None
            if ea_std is not None and def_std is not None:
                max_std = max(ea_std, def_std)
                larger_than_std = abs(abs_change) > max_std
            elif ea_std is not None:
                larger_than_std = abs(abs_change) > ea_std
            elif def_std is not None:
                larger_than_std = abs(abs_change) > def_std
            else:
                larger_than_std = None

            rows.append({
                "scenario":        scen,
                "metric":          label,
                "default_value":   f"{def_val:.4f}" if def_val is not None else "",
                "ea_value":        f"{ea_val:.4f}"  if ea_val  is not None else "",
                "abs_change":      f"{abs_change:.4f}",
                "delta_pct":       f"{delta_pct:.2f}" if delta_pct is not None else "N/A",
                "default_std":     f"{def_std:.4f}" if def_std is not None else "",
                "ea_std":          f"{ea_std:.4f}"  if ea_std  is not None else "",
                "larger_than_std": str(larger_than_std) if larger_than_std is not None else "",
            })

    return rows


def main():
    if not SUMMARY_CSV.exists():
        print(f"ERROR: {SUMMARY_CSV} does not exist.")
        print("Run scripts/run-experiments.sh and scripts/analyze_results.py first.")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    data = load_summary(SUMMARY_CSV)
    rows = compute_deltas(data)

    fieldnames = [
        "scenario", "metric",
        "default_value", "ea_value",
        "abs_change", "delta_pct",
        "default_std", "ea_std",
        "larger_than_std",
    ]
    with open(DELTAS_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n[Saved] {DELTAS_CSV}  ({len(rows)} rows)")
    print("\nDelta summary (energy-aware vs default):")
    print(f"  {'Scenario':<12} {'Metric':<25} {'Default':>10} {'EA':>10} "
          f"{'Δ%':>8}  {'> 1σ?':<8}")
    print("  " + "-" * 78)
    for r in rows:
        print(f"  {r['scenario']:<12} {r['metric']:<25} {r['default_value']:>10} "
              f"{r['ea_value']:>10} {r['delta_pct']:>8}  {r['larger_than_std']:<8}")


if __name__ == "__main__":
    main()
