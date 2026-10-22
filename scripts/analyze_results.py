#!/usr/bin/env python3
"""
scripts/analyze_results.py
Analyzes Week 5 experiment outputs, creates summary.csv, prints summary table,
and generates publication-quality charts.
"""

import os, json, glob, csv, re
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

# Power model parameters (docs/power-model.md)
POWER_PROFILES = {
    "energy-worker":  {"p_idle": 20.0, "p_max": 60.0},
    "energy-worker2": {"p_idle": 40.0, "p_max": 120.0},
    "energy-worker3": {"p_idle": 80.0, "p_max": 200.0},
}

BASE_DIR = Path(__file__).resolve().parent.parent
RESULTS_DIR = BASE_DIR / "results" / "week5"
CHARTS_DIR = RESULTS_DIR / "charts"
SUMMARY_CSV = RESULTS_DIR / "summary.csv"

def parse_run(run_dir):
    """Parses a single run directory and extracts metrics."""
    pods_file = run_dir / "pods.json"
    util_file = run_dir / "utilization.json"
    latency_file = run_dir / "latency.txt"
    
    # 1. Node Placements
    placements = {"energy-worker": 0, "energy-worker2": 0, "energy-worker3": 0}
    if pods_file.exists():
        try:
            with open(pods_file, "r") as f:
                pods_data = json.load(f)
                for item in pods_data.get("items", []):
                    node = item.get("spec", {}).get("nodeName")
                    if node in placements:
                        placements[node] += 1
        except Exception as e:
            print(f"Error reading {pods_file}: {e}")

    # 2. Node Utilization & Power Calculation
    utilization = {"energy-worker": 0.0, "energy-worker2": 0.0, "energy-worker3": 0.0}
    if util_file.exists():
        try:
            with open(util_file, "r") as f:
                util_data = json.load(f)
                results = util_data.get("data", {}).get("result", [])
                for res in results:
                    node = res.get("metric", {}).get("nodename")
                    if not node:
                        node = res.get("metric", {}).get("node")
                    if node in utilization:
                        val = float(res.get("value", [0, 0])[1])
                        utilization[node] = max(0.0, min(100.0, val))
        except Exception as e:
            print(f"Error reading {util_file}: {e}")

    # Calculate cluster power: sum of P_i over worker nodes
    total_power = 0.0
    for node, prof in POWER_PROFILES.items():
        u_frac = utilization[node] / 100.0
        p_node = prof["p_idle"] + (prof["p_max"] - prof["p_idle"]) * u_frac
        total_power += p_node

    # 3. Scheduling Delay
    delays = []
    if latency_file.exists():
        try:
            with open(latency_file, "r") as f:
                content = f.read()
                # Parse lines with delay column or the summary line
                # Format: Pod Created Scheduled Delay(s)
                for line in content.splitlines():
                    parts = line.split()
                    if len(parts) >= 4 and not parts[0].startswith("Pod") and not parts[0].startswith("-"):
                        try:
                            d = float(parts[-1])
                            delays.append(d)
                        except ValueError:
                            pass
        except Exception as e:
            print(f"Error reading {latency_file}: {e}")

    mean_delay = float(np.mean(delays)) if delays else 0.0
    min_delay = float(np.min(delays)) if delays else 0.0
    max_delay = float(np.max(delays)) if delays else 0.0

    return {
        "placements": placements,
        "utilization": utilization,
        "total_power": total_power,
        "delays": delays,
        "mean_delay": mean_delay,
        "min_delay": min_delay,
        "max_delay": max_delay,
    }

def main():
    if not RESULTS_DIR.exists():
        print(f"Directory {RESULTS_DIR} does not exist. Please run experiments first.")
        return

    scenarios = ["scenario1", "scenario2", "scenario3", "scenario4"]
    schedulers = ["default", "energy-aware"]
    
    summary_rows = []
    
    print("\n" + "="*90)
    print(f"{'Scenario':<12} {'Scheduler':<15} {'Power(W)':<10} {'Delay Mean(s)':<14} {'Worker1(eff)':<14} {'Worker2(med)':<14} {'Worker3(pwr)':<14}")
    print("="*90)

    # For Scenario 4 detailed utilization spread chart
    scen4_util_data = {"default": {}, "energy-aware": {}}

    for scen in scenarios:
        for sched in schedulers:
            runs_data = []
            for run_num in [1, 2, 3]:
                run_dir = RESULTS_DIR / scen / sched / f"run{run_num}"
                if run_dir.exists():
                    data = parse_run(run_dir)
                    runs_data.append(data)
            
            if not runs_data:
                print(f"WARNING: No data found for {scen} / {sched}")
                continue

            # Aggregate across the 3 runs
            avg_power = float(np.mean([r["total_power"] for r in runs_data]))
            all_delays = [d for r in runs_data for d in r["delays"]]
            avg_delay = float(np.mean(all_delays)) if all_delays else 0.0
            min_delay = float(np.min(all_delays)) if all_delays else 0.0
            max_delay = float(np.max(all_delays)) if all_delays else 0.0

            avg_w1_placed = float(np.mean([r["placements"]["energy-worker"] for r in runs_data]))
            avg_w2_placed = float(np.mean([r["placements"]["energy-worker2"] for r in runs_data]))
            avg_w3_placed = float(np.mean([r["placements"]["energy-worker3"] for r in runs_data]))

            avg_w1_util = float(np.mean([r["utilization"]["energy-worker"] for r in runs_data]))
            avg_w2_util = float(np.mean([r["utilization"]["energy-worker2"] for r in runs_data]))
            avg_w3_util = float(np.mean([r["utilization"]["energy-worker3"] for r in runs_data]))

            if scen == "scenario4":
                scen4_util_data[sched] = {
                    "energy-worker (eff)": avg_w1_util,
                    "energy-worker2 (med)": avg_w2_util,
                    "energy-worker3 (pwr)": avg_w3_util,
                }

            row = {
                "scenario": scen,
                "scheduler": sched,
                "total_estimated_power_W": round(avg_power, 2),
                "mean_scheduling_delay_s": round(avg_delay, 3),
                "min_scheduling_delay_s": round(min_delay, 3),
                "max_scheduling_delay_s": round(max_delay, 3),
                "placements_energy_worker_eff": round(avg_w1_placed, 1),
                "placements_energy_worker2_med": round(avg_w2_placed, 1),
                "placements_energy_worker3_pwr": round(avg_w3_placed, 1),
                "util_energy_worker_pct": round(avg_w1_util, 2),
                "util_energy_worker2_pct": round(avg_w2_util, 2),
                "util_energy_worker3_pct": round(avg_w3_util, 2),
            }
            summary_rows.append(row)

            w1_str = f"{avg_w1_placed:.0f}p ({avg_w1_util:.1f}%)"
            w2_str = f"{avg_w2_placed:.0f}p ({avg_w2_util:.1f}%)"
            w3_str = f"{avg_w3_placed:.0f}p ({avg_w3_util:.1f}%)"

            print(f"{scen:<12} {sched:<15} {avg_power:<10.2f} {avg_delay:<14.3f} {w1_str:<14} {w2_str:<14} {w3_str:<14}")

    print("="*90)

    # Write summary.csv
    fieldnames = [
        "scenario", "scheduler", "total_estimated_power_W",
        "mean_scheduling_delay_s", "min_scheduling_delay_s", "max_scheduling_delay_s",
        "placements_energy_worker_eff", "placements_energy_worker2_med", "placements_energy_worker3_pwr",
        "util_energy_worker_pct", "util_energy_worker2_pct", "util_energy_worker3_pct",
    ]
    with open(SUMMARY_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"\n[Saved] Summary CSV: {SUMMARY_CSV}")

    # Generate Charts
    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    generate_charts(summary_rows, scen4_util_data)

def generate_charts(summary_rows, scen4_util_data):
    """Generates the three required publication-quality charts."""
    scenarios = ["scenario1", "scenario2", "scenario3", "scenario4"]
    scen_labels = ["Scenario 1\n(Low)", "Scenario 2\n(Medium)", "Scenario 3\n(High)", "Scenario 4\n(Mixed)"]
    x = np.arange(len(scenarios))
    bar_width = 0.35

    # Chart 1: Grouped bar chart of total estimated power per scheduler
    def_power = [next(r["total_estimated_power_W"] for r in summary_rows if r["scenario"] == s and r["scheduler"] == "default") for s in scenarios]
    ea_power = [next(r["total_estimated_power_W"] for r in summary_rows if r["scenario"] == s and r["scheduler"] == "energy-aware") for s in scenarios]

    plt.figure(figsize=(9, 5))
    plt.bar(x - bar_width/2, def_power, bar_width, label="Default Scheduler", color="#5C6BC0")
    plt.bar(x + bar_width/2, ea_power, bar_width, label="Energy-Aware Scheduler", color="#26A69A")
    plt.xlabel("Evaluation Scenario", fontsize=11, fontweight="bold")
    plt.ylabel("Total Estimated Cluster Power (Watts)", fontsize=11, fontweight="bold")
    plt.title("Cluster Power Consumption Comparison by Workload Scenario", fontsize=12, fontweight="bold")
    plt.xticks(x, scen_labels)
    plt.legend(frameon=True)
    plt.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    chart1_path = CHARTS_DIR / "power_by_scenario.png"
    plt.savefig(chart1_path, dpi=300)
    plt.close()
    print(f"[Saved] Power Comparison Chart: {chart1_path}")

    # Chart 2: Grouped bar chart of mean scheduling delay per scheduler
    def_delay = [next(r["mean_scheduling_delay_s"] for r in summary_rows if r["scenario"] == s and r["scheduler"] == "default") for s in scenarios]
    ea_delay = [next(r["mean_scheduling_delay_s"] for r in summary_rows if r["scenario"] == s and r["scheduler"] == "energy-aware") for s in scenarios]

    plt.figure(figsize=(9, 5))
    plt.bar(x - bar_width/2, def_delay, bar_width, label="Default Scheduler", color="#78909C")
    plt.bar(x + bar_width/2, ea_delay, bar_width, label="Energy-Aware Scheduler", color="#FF7043")
    plt.xlabel("Evaluation Scenario", fontsize=11, fontweight="bold")
    plt.ylabel("Mean Scheduling Delay (Seconds)", fontsize=11, fontweight="bold")
    plt.title("Mean Scheduling Latency Comparison by Workload Scenario", fontsize=12, fontweight="bold")
    plt.xticks(x, scen_labels)
    plt.legend(frameon=True)
    plt.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    chart2_path = CHARTS_DIR / "latency_by_scenario.png"
    plt.savefig(chart2_path, dpi=300)
    plt.close()
    print(f"[Saved] Scheduling Latency Chart: {chart2_path}")

    # Chart 3: Per-node utilization spread for Scenario 4 (mixed workload), subplots per scheduler
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5), sharey=True)
    nodes = ["Worker 1\n(Efficient)", "Worker 2\n(Medium)", "Worker 3\n(Power-Hungry)"]
    
    def_vals = [
        scen4_util_data["default"].get("energy-worker (eff)", 0),
        scen4_util_data["default"].get("energy-worker2 (med)", 0),
        scen4_util_data["default"].get("energy-worker3 (pwr)", 0),
    ]
    ea_vals = [
        scen4_util_data["energy-aware"].get("energy-worker (eff)", 0),
        scen4_util_data["energy-aware"].get("energy-worker2 (med)", 0),
        scen4_util_data["energy-aware"].get("energy-worker3 (pwr)", 0),
    ]

    colors_def = ["#90CAF9", "#90CAF9", "#90CAF9"]
    colors_ea = ["#66BB6A", "#FFA726", "#EF5350"]

    ax1.bar(nodes, def_vals, color=colors_def, edgecolor="#37474F", width=0.5)
    ax1.set_title("Default Scheduler", fontsize=11, fontweight="bold")
    ax1.set_ylabel("CPU Utilization (%)", fontsize=11, fontweight="bold")
    ax1.set_ylim(0, 100)
    ax1.grid(axis="y", linestyle="--", alpha=0.5)

    ax2.bar(nodes, ea_vals, color=colors_ea, edgecolor="#37474F", width=0.5)
    ax2.set_title("Energy-Aware Scheduler", fontsize=11, fontweight="bold")
    ax2.grid(axis="y", linestyle="--", alpha=0.5)

    fig.suptitle("Scenario 4 (Mixed Workload): Per-Node CPU Utilization Spread", fontsize=12, fontweight="bold")
    plt.tight_layout()
    chart3_path = CHARTS_DIR / "utilization_scenario4.png"
    plt.savefig(chart3_path, dpi=300)
    plt.close()
    print(f"[Saved] Scenario 4 Utilization Spread Chart: {chart3_path}")

if __name__ == "__main__":
    main()
