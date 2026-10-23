# Paper Figures and Tables

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> A numbered list of all final figures and tables for the paper,
> with file path, suggested caption, and the paper section they belong in.

---

## Figures

### Figure 1 — Cluster Architecture

**File:** (no PNG — use the mermaid diagram from README.md or render it)  
**Caption:**  
"Figure 1. Architecture of the experimental Kind cluster. Three worker nodes
carry simulated power-profile labels (P_idle, P_max). The energy-aware
scheduler queries Prometheus for live CPU utilisation and applies the scoring
formula Score_i = wR·R_i + wL·L_i − wP·P_i to select a node."  
**Section:** Section 3 (System Design) or Section 4 (Implementation)

---

### Figure 2 — Total Estimated Cluster Power by Scenario

**File:** `results/week6/charts/power_by_scenario.png`  
**Caption:**  
"Figure 2. Total estimated cluster power (W) for the default and energy-aware
schedulers across Scenarios 1–4. Error bars represent ±1 standard deviation
over 5 independent runs. Power is estimated from the linear model
P(u) = P_idle + (P_max − P_idle)·u; no physical sensors were used."  
**Section:** Section 5 (Results) — §5.2

---

### Figure 3 — Mean Scheduling Delay by Scenario

**File:** `results/week6/charts/latency_by_scenario.png`  
**Caption:**  
"Figure 3. Mean scheduling delay (seconds) per scenario and scheduler.
Error bars represent ±1 standard deviation over 5 runs. Scheduling delay
is measured as the time from pod creation timestamp to the PodScheduled
condition transition."  
**Section:** Section 5 — §5.5

---

### Figure 4 — Per-Node CPU Utilisation Spread (Scenario 4)

**File:** `results/week6/charts/utilization_scenario4.png`  
**Caption:**  
"Figure 4. Mean CPU utilisation (%) per worker node for Scenario 4 (mixed
workload: 3 latency-sensitive nginx + 3 batch stress-ng pods). Left: default
scheduler. Right: energy-aware scheduler. Values are means over 5 runs."  
**Section:** Section 5 — §5.1

---

### Figure 5 — p95 Application Latency (Scenario 4)

**File:** `results/week6/charts/p95_latency_scenario4.png`  
**Caption:**  
"Figure 5. p95 HTTP response latency (ms) for Scenario 4, measured by a
fortio load generator (50 QPS, 4 connections, 60 s) while batch stress-ng
pods ran concurrently. Error bars represent ±1 standard deviation over 5 runs."  
**Section:** Section 5 — §5.4

---

### Figure 6 — Weight Tuning: Power vs p95 Latency Trade-off

**File:** `results/week6/charts/weight_sensitivity.png`  
**Caption:**  
"Figure 6. Scatter plot of estimated cluster power vs p95 application latency
for each weight combination in the grid search. Each point represents one
(wR, wL, wP) triple from {0.2, 0.4, 0.6}³ summing to 1. The selected
combination (★) minimised power subject to p95 within 10% of the minimum
observed p95. The vertical dashed line marks the 10% tolerance boundary."  
**Section:** Section 4 (Implementation) — §4.2 (Weight Tuning) or Appendix

---

## Tables

### Table 1 — Simulated Node Power Profiles

**File:** (inline LaTeX table in paper)  
**Caption:**  
"Table 1. Simulated power profiles applied to the three Kind worker nodes.
Values are Kubernetes node labels; no physical power measurement was performed.
idle/max ratios are consistent with SPECpower_ssj2008 server-class benchmarks."  
**Section:** Section 4 — §4.1

| Node | Tier | P_idle (W) | P_max (W) | idle/max |
|:---|:---|:---:|:---:|:---:|
| energy-worker | efficient | 20 | 60 | 0.33 |
| energy-worker2 | medium | 40 | 120 | 0.33 |
| energy-worker3 | power-hungry | 80 | 200 | 0.40 |

---

### Table 2 — Weight Profiles

**File:** (inline table)  
**Caption:**  
"Table 2. Tuned weight profiles for the two workload types, as selected by
the grid search (scripts/tune_weights.py). wR, wL, wP are the weights for
the resource-suitability, latency-suitability, and estimated-power terms."  
**Section:** Section 4 — §4.2

| Profile | Workload type | wR | wL | wP |
|:---|:---|:---:|:---:|:---:|
| Latency-sensitive | latency-sensitive | 0.2 | 0.6 | 0.2 |
| Batch | batch | 0.2 | 0.2 | 0.6 |

---

### Table 3 — Test Workload Scenarios

**File:** (inline table)  
**Caption:**  
"Table 3. Four workload scenarios used for evaluation. Each scenario was run
5 times per scheduler (40 total runs). CPU and memory values are Kubernetes
resource requests."  
**Section:** Section 4 — §4.4

| # | Description | Pods | CPU req | Mem req | Type |
|:---|:---|:---:|:---:|:---:|:---|
| 1 | Low | 2 | 50m | 32Mi | latency-sensitive |
| 2 | Medium | 6 | 200m | 128Mi | latency-sensitive |
| 3 | High | 8 | 500m | 256Mi | mixed |
| 4 | Mixed | 3+3 | 100m+250m | 64Mi+64Mi | latency+batch |

---

### Table 4 — Main Results Summary

**File:** `results/week6/summary.csv` (selected rows, rendered as table in paper)  
**Caption:**  
"Table 4. Mean (±σ) estimated cluster power (W), scheduling delay (s),
p95 latency (ms, Scenario 4 only), and utilisation spread (pct-pts) for
the default and energy-aware schedulers. Values from results/week6/summary.csv,
n=5 runs per cell. Failed runs are excluded and counted in the failed_runs column."  
**Section:** Section 5 — §5.2–5.5
