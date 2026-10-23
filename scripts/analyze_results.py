#!/usr/bin/env python3
"""
scripts/analyze_results.py
Week 6 – Analyzes Week 6 experiment outputs, creates summary.csv, prints a
summary table, and generates publication-quality charts with error bars.

Changes from Week 5:
  - RESULTS_DIR now points to results/week6/.
  - Aggregation reports mean AND standard deviation (not just mean/min/max).
  - p95 application latency (from fortio loadtest.txt) is parsed and reported
    for Scenario 4 runs.
  - Failed or missing runs are counted; their values are NOT interpolated.
  - Charts updated: bar charts now include std-dev error bars, plus a new
    bar chart of p95 latency per scheduler for Scenario 4.
  - Sensitivity chart generated from tuning.csv (power vs p95 latency scatter).

No unit tests are added or modified.
"""

import csv
import json
import os
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

# ---------------------------------------------------------------------------
# Power model (must match label-nodes.sh and docs/power-model.md)
# ---------------------------------------------------------------------------
POWER_PROFILES = {
    "energy-worker":  {"p_idle": 20.0, "p_max": 60.0},
    "energy-worker2": {"p_idle": 40.0, "p_max": 120.0},
    "energy-worker3": {"p_idle": 80.0, "p_max": 200.0},
}

BASE_DIR = Path(__file__).resolve().parent.parent
RESULTS_DIR = BASE_DIR / "results" / "week6"
CHARTS_DIR = RESULTS_DIR / "charts"
SUMMARY_CSV = RESULTS_DIR / "summary.csv"
TUNING_CSV = RESULTS_DIR / "tuning.csv"

# ---------------------------------------------------------------------------
# Per-run parsing
# ---------------------------------------------------------------------------

def parse_run(run_dir: Path) -> dict | None:
    """
    Parse one run directory.  Returns a dict of metrics or None if the run
    has a FAILED marker (meaning the run is marked as failed and should not
    contribute to aggregated statistics).
    """
    # Runs with a FAILED marker are excluded from aggregation.
    if (run_dir / "FAILED").exists():
        print(f"  [analyze] Run {run_dir} marked FAILED — excluded.")
        return None

    pods_file   = run_dir / "pods.json"
    util_file   = run_dir / "utilization.json"
    latency_file = run_dir / "latency.txt"
    loadtest_file = run_dir / "loadtest.txt"

    # ── 1. Node Placements ────────────────────────────────────────────────────
    placements = {"energy-worker": 0, "energy-worker2": 0, "energy-worker3": 0}
    if pods_file.exists():
        try:
            with open(pods_file) as f:
                pods_data = json.load(f)
            for item in pods_data.get("items", []):
                node = item.get("spec", {}).get("nodeName")
                if node in placements:
                    placements[node] += 1
        except Exception as e:
            print(f"  [analyze] Error reading {pods_file}: {e}")

    # ── 2. Node Utilisation & Power Calculation ───────────────────────────────
    utilization = {"energy-worker": 0.0, "energy-worker2": 0.0, "energy-worker3": 0.0}
    if util_file.exists():
        try:
            with open(util_file) as f:
                util_data = json.load(f)
            for res in util_data.get("data", {}).get("result", []):
                node = (res.get("metric", {}).get("nodename")
                        or res.get("metric", {}).get("node"))
                if node in utilization:
                    val = float(res.get("value", [0, 0])[1])
                    utilization[node] = max(0.0, min(100.0, val))
        except Exception as e:
            print(f"  [analyze] Error reading {util_file}: {e}")

    total_power = sum(
        prof["p_idle"] + (prof["p_max"] - prof["p_idle"]) * (utilization[node] / 100.0)
        for node, prof in POWER_PROFILES.items()
    )

    util_vals = [utilization[n] for n in POWER_PROFILES]
    util_spread = max(util_vals) - min(util_vals)

    # ── 3. Scheduling Delay ───────────────────────────────────────────────────
    delays = []
    if latency_file.exists():
        try:
            with open(latency_file) as f:
                content = f.read()
            for line in content.splitlines():
                parts = line.split()
                if (len(parts) >= 4
                        and not parts[0].startswith("Pod")
                        and not parts[0].startswith("-")):
                    try:
                        d = float(parts[-1])
                        delays.append(d)
                    except ValueError:
                        pass
        except Exception as e:
            print(f"  [analyze] Error reading {latency_file}: {e}")

    # ── 4. p95 Application Latency (fortio, Scenario 4 only) ─────────────────
    p95_ms = None
    if loadtest_file.exists():
        try:
            with open(loadtest_file) as f:
                content = f.read()
            if "LOAD_TEST_FAILED" not in content and "LOG_CAPTURE_FAILED" not in content:
                p95_ms = _parse_fortio_p95(content)
        except Exception as e:
            print(f"  [analyze] Error reading {loadtest_file}: {e}")

    return {
        "placements": placements,
        "utilization": utilization,
        "total_power": total_power,
        "util_spread": util_spread,
        "delays": delays,
        "p95_ms": p95_ms,
    }


def _parse_fortio_p95(text: str) -> float | None:
    """
    Extract p95 latency in milliseconds from fortio text output.
    Fortio prints lines like:  '95.00 % <= 18.9 ms'
    """
    pattern = re.compile(
        r'95\.00\s*%\s*<=\s*([0-9]+(?:\.[0-9]+)?)\s*(ms|µs|us|s)',
        re.IGNORECASE
    )
    for line in text.splitlines():
        m = pattern.search(line)
        if m:
            val = float(m.group(1))
            unit = m.group(2).lower()
            if unit in ("µs", "us"):
                val /= 1000.0
            elif unit == "s":
                val *= 1000.0
            return round(val, 3)
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not RESULTS_DIR.exists():
        print(f"Directory {RESULTS_DIR} does not exist.  Run experiments first.")
        return

    scenarios  = ["scenario1", "scenario2", "scenario3", "scenario4"]
    schedulers = ["default", "energy-aware"]

    summary_rows = []

    print("\n" + "="*110)
    header = (
        f"{'Scenario':<12} {'Scheduler':<15} "
        f"{'Power μ(W)':<12} {'Power σ':<9} "
        f"{'Delay μ(s)':<12} {'Delay σ':<9} "
        f"{'p95 μ(ms)':<11} {'p95 σ':<8} "
        f"{'Spread μ':<10} {'Spread σ':<8} "
        f"{'Runs':<6} {'Failed':<6}"
    )
    print(header)
    print("="*110)

    # For Scenario 4 utilisation-spread subplot.
    scen4_util_data = {"default": {}, "energy-aware": {}}

    for scen in scenarios:
        for sched in schedulers:
            all_runs_data = []
            failed_count = 0

            for run_num in range(1, 6):   # 5 runs per combination
                run_dir = RESULTS_DIR / scen / sched / f"run{run_num}"
                if not run_dir.exists():
                    # Missing directory counts as failed.
                    failed_count += 1
                    continue
                data = parse_run(run_dir)
                if data is None:
                    failed_count += 1
                else:
                    all_runs_data.append(data)

            total_runs = len(all_runs_data) + failed_count

            if not all_runs_data:
                print(f"WARNING: No valid data for {scen}/{sched} "
                      f"({failed_count}/{total_runs} failed).")
                continue

            # ── Aggregate ────────────────────────────────────────────────────
            powers = [r["total_power"] for r in all_runs_data]
            all_delays = [d for r in all_runs_data for d in r["delays"]]
            spreads = [r["util_spread"] for r in all_runs_data]

            # p95 from fortio — only populated for Scenario 4
            p95_vals = [r["p95_ms"] for r in all_runs_data
                        if r["p95_ms"] is not None]

            avg_power = float(np.mean(powers))
            std_power = float(np.std(powers, ddof=1)) if len(powers) > 1 else 0.0

            avg_delay = float(np.mean(all_delays)) if all_delays else 0.0
            std_delay = float(np.std(all_delays, ddof=1)) if len(all_delays) > 1 else 0.0

            avg_p95 = float(np.mean(p95_vals)) if p95_vals else None
            std_p95 = float(np.std(p95_vals, ddof=1)) if len(p95_vals) > 1 else 0.0

            avg_spread = float(np.mean(spreads))
            std_spread = float(np.std(spreads, ddof=1)) if len(spreads) > 1 else 0.0

            # Mean placements
            avg_w1 = float(np.mean([r["placements"]["energy-worker"] for r in all_runs_data]))
            avg_w2 = float(np.mean([r["placements"]["energy-worker2"] for r in all_runs_data]))
            avg_w3 = float(np.mean([r["placements"]["energy-worker3"] for r in all_runs_data]))

            # Mean utilisation
            avg_u1 = float(np.mean([r["utilization"]["energy-worker"] for r in all_runs_data]))
            avg_u2 = float(np.mean([r["utilization"]["energy-worker2"] for r in all_runs_data]))
            avg_u3 = float(np.mean([r["utilization"]["energy-worker3"] for r in all_runs_data]))

            if scen == "scenario4":
                scen4_util_data[sched] = {
                    "energy-worker (eff)": avg_u1,
                    "energy-worker2 (med)": avg_u2,
                    "energy-worker3 (pwr)": avg_u3,
                }

            row = {
                "scenario":   scen,
                "scheduler":  sched,
                "valid_runs": len(all_runs_data),
                "failed_runs": failed_count,
                # Power
                "mean_total_power_W":  round(avg_power, 2),
                "std_total_power_W":   round(std_power, 2),
                # Scheduling delay
                "mean_scheduling_delay_s": round(avg_delay, 3),
                "std_scheduling_delay_s":  round(std_delay, 3),
                # p95 application latency (Scenario 4 only)
                "mean_p95_latency_ms":  round(avg_p95, 3) if avg_p95 is not None else "",
                "std_p95_latency_ms":   round(std_p95, 3) if p95_vals else "",
                # Utilisation spread
                "mean_util_spread_pct": round(avg_spread, 2),
                "std_util_spread_pct":  round(std_spread, 2),
                # Node placements
                "placements_energy_worker_eff":   round(avg_w1, 1),
                "placements_energy_worker2_med":  round(avg_w2, 1),
                "placements_energy_worker3_pwr":  round(avg_w3, 1),
                # Node utilisation
                "util_energy_worker_pct":  round(avg_u1, 2),
                "util_energy_worker2_pct": round(avg_u2, 2),
                "util_energy_worker3_pct": round(avg_u3, 2),
            }
            summary_rows.append(row)

            p95_str = f"{avg_p95:.1f}" if avg_p95 is not None else "N/A"
            p95_std_str = f"±{std_p95:.1f}" if p95_vals else "N/A"
            print(
                f"{scen:<12} {sched:<15} "
                f"{avg_power:<12.2f} ±{std_power:<7.2f} "
                f"{avg_delay:<12.3f} ±{std_delay:<7.3f} "
                f"{p95_str:<11} {p95_std_str:<8} "
                f"{avg_spread:<10.2f} ±{std_spread:<6.2f} "
                f"{len(all_runs_data):<6} {failed_count:<6}"
            )

    print("="*110)

    # ── Write summary.csv ─────────────────────────────────────────────────────
    fieldnames = [
        "scenario", "scheduler", "valid_runs", "failed_runs",
        "mean_total_power_W", "std_total_power_W",
        "mean_scheduling_delay_s", "std_scheduling_delay_s",
        "mean_p95_latency_ms", "std_p95_latency_ms",
        "mean_util_spread_pct", "std_util_spread_pct",
        "placements_energy_worker_eff", "placements_energy_worker2_med",
        "placements_energy_worker3_pwr",
        "util_energy_worker_pct", "util_energy_worker2_pct",
        "util_energy_worker3_pct",
    ]
    with open(SUMMARY_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)
    print(f"\n[Saved] Summary CSV: {SUMMARY_CSV}")

    # ── Generate Charts ───────────────────────────────────────────────────────
    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    generate_charts(summary_rows, scen4_util_data)


# ---------------------------------------------------------------------------
# Chart generation
# ---------------------------------------------------------------------------

def _get_val(rows, scenario, scheduler, key, default=0.0):
    for r in rows:
        if r["scenario"] == scenario and r["scheduler"] == scheduler:
            v = r.get(key, default)
            return float(v) if v != "" else 0.0
    return default


def generate_charts(summary_rows, scen4_util_data):
    scenarios    = ["scenario1", "scenario2", "scenario3", "scenario4"]
    scen_labels  = ["Scenario 1\n(Low)", "Scenario 2\n(Medium)",
                    "Scenario 3\n(High)", "Scenario 4\n(Mixed)"]
    x = np.arange(len(scenarios))
    bw = 0.35

    # ── Chart 1: Total Estimated Power with error bars ────────────────────────
    def_power = [_get_val(summary_rows, s, "default",       "mean_total_power_W") for s in scenarios]
    ea_power  = [_get_val(summary_rows, s, "energy-aware",  "mean_total_power_W") for s in scenarios]
    def_power_std = [_get_val(summary_rows, s, "default",      "std_total_power_W") for s in scenarios]
    ea_power_std  = [_get_val(summary_rows, s, "energy-aware", "std_total_power_W") for s in scenarios]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.bar(x - bw/2, def_power, bw, label="Default Scheduler",
           color="#5C6BC0", yerr=def_power_std, capsize=4, ecolor="#333")
    ax.bar(x + bw/2, ea_power, bw, label="Energy-Aware Scheduler",
           color="#26A69A", yerr=ea_power_std, capsize=4, ecolor="#333")
    ax.set_xlabel("Evaluation Scenario", fontsize=11, fontweight="bold")
    ax.set_ylabel("Total Estimated Cluster Power (Watts)", fontsize=11, fontweight="bold")
    ax.set_title("Cluster Power Consumption Comparison by Workload Scenario\n"
                 "(error bars = 1 std dev, n=5 runs)", fontsize=11, fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(scen_labels)
    ax.legend(frameon=True)
    ax.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    p1 = CHARTS_DIR / "power_by_scenario.png"
    fig.savefig(p1, dpi=300)
    plt.close(fig)
    print(f"[Saved] {p1}")

    # ── Chart 2: Scheduling Delay with error bars ─────────────────────────────
    def_delay     = [_get_val(summary_rows, s, "default",      "mean_scheduling_delay_s") for s in scenarios]
    ea_delay      = [_get_val(summary_rows, s, "energy-aware", "mean_scheduling_delay_s") for s in scenarios]
    def_delay_std = [_get_val(summary_rows, s, "default",      "std_scheduling_delay_s") for s in scenarios]
    ea_delay_std  = [_get_val(summary_rows, s, "energy-aware", "std_scheduling_delay_s") for s in scenarios]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.bar(x - bw/2, def_delay, bw, label="Default Scheduler",
           color="#78909C", yerr=def_delay_std, capsize=4, ecolor="#333")
    ax.bar(x + bw/2, ea_delay, bw, label="Energy-Aware Scheduler",
           color="#FF7043", yerr=ea_delay_std, capsize=4, ecolor="#333")
    ax.set_xlabel("Evaluation Scenario", fontsize=11, fontweight="bold")
    ax.set_ylabel("Mean Scheduling Delay (Seconds)", fontsize=11, fontweight="bold")
    ax.set_title("Mean Scheduling Latency Comparison by Workload Scenario\n"
                 "(error bars = 1 std dev, n=5 runs)", fontsize=11, fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(scen_labels)
    ax.legend(frameon=True)
    ax.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    p2 = CHARTS_DIR / "latency_by_scenario.png"
    fig.savefig(p2, dpi=300)
    plt.close(fig)
    print(f"[Saved] {p2}")

    # ── Chart 3: Per-node utilisation spread for Scenario 4 ──────────────────
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5), sharey=True)
    nodes = ["Worker 1\n(Efficient)", "Worker 2\n(Medium)", "Worker 3\n(Power-Hungry)"]

    def_vals = [
        scen4_util_data.get("default", {}).get("energy-worker (eff)", 0),
        scen4_util_data.get("default", {}).get("energy-worker2 (med)", 0),
        scen4_util_data.get("default", {}).get("energy-worker3 (pwr)", 0),
    ]
    ea_vals = [
        scen4_util_data.get("energy-aware", {}).get("energy-worker (eff)", 0),
        scen4_util_data.get("energy-aware", {}).get("energy-worker2 (med)", 0),
        scen4_util_data.get("energy-aware", {}).get("energy-worker3 (pwr)", 0),
    ]

    ax1.bar(nodes, def_vals, color=["#90CAF9"]*3, edgecolor="#37474F", width=0.5)
    ax1.set_title("Default Scheduler", fontsize=11, fontweight="bold")
    ax1.set_ylabel("CPU Utilisation (%)", fontsize=11, fontweight="bold")
    ax1.set_ylim(0, 100)
    ax1.grid(axis="y", linestyle="--", alpha=0.5)

    ax2.bar(nodes, ea_vals, color=["#66BB6A", "#FFA726", "#EF5350"],
            edgecolor="#37474F", width=0.5)
    ax2.set_title("Energy-Aware Scheduler", fontsize=11, fontweight="bold")
    ax2.grid(axis="y", linestyle="--", alpha=0.5)

    fig.suptitle("Scenario 4 (Mixed): Per-Node CPU Utilisation Spread", fontsize=12, fontweight="bold")
    plt.tight_layout()
    p3 = CHARTS_DIR / "utilization_scenario4.png"
    fig.savefig(p3, dpi=300)
    plt.close(fig)
    print(f"[Saved] {p3}")

    # ── Chart 4: p95 Application Latency for Scenario 4 ─────────────────────
    def_p95 = _get_val(summary_rows, "scenario4", "default",      "mean_p95_latency_ms")
    ea_p95  = _get_val(summary_rows, "scenario4", "energy-aware", "mean_p95_latency_ms")
    def_p95_std = _get_val(summary_rows, "scenario4", "default",      "std_p95_latency_ms")
    ea_p95_std  = _get_val(summary_rows, "scenario4", "energy-aware", "std_p95_latency_ms")

    if def_p95 > 0 or ea_p95 > 0:
        fig, ax = plt.subplots(figsize=(6, 5))
        bars = ax.bar(
            ["Default\nScheduler", "Energy-Aware\nScheduler"],
            [def_p95, ea_p95],
            color=["#5C6BC0", "#26A69A"],
            yerr=[def_p95_std, ea_p95_std],
            capsize=6, ecolor="#333", width=0.5
        )
        ax.set_ylabel("p95 Application Latency (ms)", fontsize=11, fontweight="bold")
        ax.set_title("Scenario 4 (Mixed Workload): p95 Latency\n"
                     "fortio 50 QPS × 60 s, batch pods concurrent\n"
                     "(error bars = 1 std dev, n=5 runs)",
                     fontsize=10, fontweight="bold")
        ax.grid(axis="y", linestyle="--", alpha=0.6)
        # Annotate bars with values.
        for bar, val in zip(bars, [def_p95, ea_p95]):
            if val > 0:
                ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 0.5,
                        f"{val:.1f} ms", ha="center", va="bottom", fontsize=10)
        plt.tight_layout()
        p4 = CHARTS_DIR / "p95_latency_scenario4.png"
        fig.savefig(p4, dpi=300)
        plt.close(fig)
        print(f"[Saved] {p4}")
    else:
        print("[Skipped] p95 latency chart — no fortio data available yet.")

    # ── Chart 5: Sensitivity scatter plot from tuning.csv ────────────────────
    if TUNING_CSV.exists():
        _generate_sensitivity_chart()
    else:
        print(f"[Skipped] Sensitivity chart — {TUNING_CSV} not found yet.")


def _generate_sensitivity_chart():
    """
    Scatter plot: estimated power vs p95 latency for each weight combo.
    The best combination (lowest power within 10% of best p95) is highlighted.
    """
    rows = []
    with open(TUNING_CSV, newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            if r["status"] == "ok" and r["total_power_W"] and r["p95_latency_ms"]:
                rows.append({
                    "combo_id":    r["combo_id"],
                    "power":       float(r["total_power_W"]),
                    "p95":         float(r["p95_latency_ms"]),
                    "lat_wR":      r["lat_wR"],
                    "lat_wL":      r["lat_wL"],
                    "lat_wP":      r["lat_wP"],
                })

    if not rows:
        print("[Skipped] Sensitivity scatter — no OK rows in tuning.csv.")
        return

    # Identify best combination (same rule as tune_weights.py).
    p95_min = min(r["p95"] for r in rows)
    threshold = p95_min * 1.10
    candidates = [r for r in rows if r["p95"] <= threshold]
    best = min(candidates, key=lambda r: r["power"]) if candidates else None

    powers = [r["power"] for r in rows]
    p95s   = [r["p95"]   for r in rows]

    fig, ax = plt.subplots(figsize=(8, 6))

    for r in rows:
        is_best = best and r["combo_id"] == best["combo_id"]
        color  = "#E53935" if is_best else "#1E88E5"
        marker = "*"       if is_best else "o"
        size   = 200       if is_best else 80
        zorder = 5         if is_best else 3
        ax.scatter(r["p95"], r["power"],
                   c=color, marker=marker, s=size, zorder=zorder,
                   label=("Best combo" if is_best else None))
        ax.annotate(
            f"{r['combo_id']}\n(wR={r['lat_wR']} wL={r['lat_wL']} wP={r['lat_wP']})",
            xy=(r["p95"], r["power"]),
            xytext=(5, 5), textcoords="offset points",
            fontsize=7, color="#333"
        )

    ax.set_xlabel("p95 Application Latency (ms)", fontsize=11, fontweight="bold")
    ax.set_ylabel("Total Estimated Cluster Power (W)", fontsize=11, fontweight="bold")
    ax.set_title("Weight Tuning: Power vs p95 Latency Trade-off\n"
                 "(★ = selected best combination)", fontsize=11, fontweight="bold")
    ax.grid(linestyle="--", alpha=0.5)

    # Add tolerance boundary line.
    ax.axvline(threshold, color="#FB8C00", linestyle="--", linewidth=1.2,
               label=f"p95 ≤ {threshold:.1f} ms (10% over best)")
    ax.legend(frameon=True, fontsize=9)

    plt.tight_layout()
    p5 = CHARTS_DIR / "weight_sensitivity.png"
    fig.savefig(p5, dpi=300)
    plt.close(fig)
    print(f"[Saved] {p5}")


if __name__ == "__main__":
    main()
