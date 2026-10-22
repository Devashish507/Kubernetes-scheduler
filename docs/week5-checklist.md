# Week 5 Verification Checklist

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> **Milestone**: Week 5 — Full Experimental Campaign, Results Aggregation, and Charts

---

## 1. Deliverables Verification Summary

| Check | Deliverable | Location | Status |
| :---: | :--- | :--- | :---: |
| ✅ | Scenario Workload Manifests (8 manifests) | `workloads/scenarios/scenario[1-4]-{default,energy-aware}.yaml` | VERIFIED |
| ✅ | Automated Experiment Runner | `scripts/run-experiments.sh` | VERIFIED |
| ✅ | Raw Experimental Data (24 runs) | `results/week5/scenario[1-4]/{default,energy-aware}/run[1-3]/` | VERIFIED |
| ✅ | Aggregated Summary CSV (8 rows + header) | `results/week5/summary.csv` | VERIFIED |
| ✅ | Publication Charts (3 PNGs) | `results/week5/charts/*.png` | VERIFIED |
| ✅ | Results Analysis Script | `scripts/analyze_results.py` | VERIFIED |
| ✅ | Results Narrative Draft | `docs/week5-results-draft.md` | VERIFIED |
| ✅ | Baseline Constraint Compliance | `docs/peaks-setup.md` checked; PEAKS excluded | VERIFIED |

---

## 2. Verification Steps and Commands

### Step 1: Verify Manifest Generation
Ensure all 8 workload scenario files exist and contain proper scheduler specifications:
```bash
ls -l workloads/scenarios/
```
**Expected Output:**
- `scenario1-default.yaml`, `scenario1-energy-aware.yaml`
- `scenario2-default.yaml`, `scenario2-energy-aware.yaml`
- `scenario3-default.yaml`, `scenario3-energy-aware.yaml`
- `scenario4-default.yaml`, `scenario4-energy-aware.yaml`

---

### Step 2: Verify `summary.csv` Row Count & Content
Check that `results/week5/summary.csv` exists and has exactly 9 lines (header + 8 scenario x scheduler combinations):
```bash
wc -l results/week5/summary.csv
```
**Expected Output:**
```text
9 results/week5/summary.csv
```

Print the entire CSV:
```bash
cat results/week5/summary.csv
```

**Sample Row (Expected Format and Output):**
```text
scenario,scheduler,total_estimated_power_W,mean_scheduling_delay_s,min_scheduling_delay_s,max_scheduling_delay_s,placements_energy_worker_eff,placements_energy_worker2_med,placements_energy_worker3_pwr,util_energy_worker_pct,util_energy_worker2_pct,util_energy_worker3_pct
scenario1,energy-aware,150.1,0.0,0.0,0.0,1.0,1.0,0.0,4.21,4.21,4.2
```

---

### Step 3: Verify Publication Charts
Ensure the 3 required PNG figures exist in `results/week5/charts/`:
```bash
ls -lh results/week5/charts/
```
**Expected Files:**
1. `power_by_scenario.png`: Grouped bar chart comparing total estimated cluster power per scheduler across Scenarios 1–4.
2. `latency_by_scenario.png`: Grouped bar chart comparing mean pod scheduling delay across Scenarios 1–4.
3. `utilization_scenario4.png`: Side-by-side subplot bar chart of per-node CPU utilization spread for Scenario 4 (Mixed Workload).

---

### Step 4: Verify Re-execution of Analysis Pipeline
Re-running the Python aggregator produces a consistent summary table and refreshes charts:
```bash
python scripts/analyze_results.py
```
**Expected Output:**
Human-readable summary table printed to stdout confirming:
- Total Power (W)
- Mean Scheduling Delay (s)
- Pod Placements per Node Tier (Efficient / Medium / Power-Hungry)
- Node CPU Utilization percentages (%)

---

## 3. Policy and Constraint Conformance
- **No Tests Policy**: Zero unit tests, integration test files, or test frameworks were created or modified.
- **Data Integrity Policy**: All data in `summary.csv` was empirically measured and collected from live runs; no numbers were fabricated or interpolated.
- **PEAKS Exclusion**: PEAKS was reviewed via `docs/peaks-setup.md` and excluded due to KIND Kepler constraints.
