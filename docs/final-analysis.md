# Final Analysis

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> All numeric values cited here are taken directly from `results/week6/summary.csv`
> and `results/week6/tuning.csv` via `scripts/compute_deltas.py` →
> `results/week7/deltas.csv`. No values are computed by hand.  
> Run `python3 scripts/compute_deltas.py` to regenerate `deltas.csv`.

> **Note:** This document contains `[CSV]` placeholders wherever a value must
> be read from the CSV files after the experiments complete. Every `[CSV]` tag
> references a specific column and row in `summary.csv` or `deltas.csv`.
> Do not fill these in by hand — copy the exact numbers from the CSVs.

---

## 1. Per-Scenario Analysis

### Scenario 1 — Low Load (2 latency-sensitive pods)

**What the energy-aware scheduler did differently:**

| Metric | Default | Energy-Aware | Δ% | > 1σ? |
|:---|:---:|:---:|:---:|:---:|
| Total estimated power (W) | `[CSV: scenario1/default/mean_total_power_W]` | `[CSV: scenario1/ea/mean_total_power_W]` | `[CSV: deltas.csv]` | `[CSV]` |
| Scheduling delay (s) | `[CSV: scenario1/default/mean_scheduling_delay_s]` | `[CSV: scenario1/ea/mean_scheduling_delay_s]` | `[CSV]` | `[CSV]` |
| Utilisation spread (pct-pts) | `[CSV: scenario1/default/mean_util_spread_pct]` | `[CSV: scenario1/ea/mean_util_spread_pct]` | `[CSV]` | `[CSV]` |

**Placement:** The default scheduler placed `[CSV: placements_energy_worker3_pwr]` pods
on the power-hungry node (`energy-worker3`). The energy-aware scheduler placed
`[CSV: ea placements_energy_worker3_pwr]` pods on that node.

**Interpretation:** At low load, the utilisation signal available to the
`L_i` and `P_i` terms is weak (all nodes near 0% utilisation), so score
differentiation is dominated by `R_i`. Whether any difference is larger
than the standard deviation is indicated by the `larger_than_std` column in
`deltas.csv`. If `False`, the difference is within noise.

---

### Scenario 2 — Medium Load (6 latency-sensitive pods)

| Metric | Default | Energy-Aware | Δ% | > 1σ? |
|:---|:---:|:---:|:---:|:---:|
| Total estimated power (W) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Scheduling delay (s) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Utilisation spread (pct-pts) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

**Placement:** Default placed `[CSV]` pods on `energy-worker` (efficient),
`[CSV]` on `energy-worker2` (medium), `[CSV]` on `energy-worker3` (power-hungry).
Energy-aware placed `[CSV]` / `[CSV]` / `[CSV]`.

**Interpretation:** With more pods the utilisation spread increases and the
`P_i` penalty on `energy-worker3` becomes visible. Whether the energy-aware
scheduler concentrates pods on the efficient node is visible in the
`placements_energy_worker_eff` column.

---

### Scenario 3 — High Load (8 pods, high CPU request)

| Metric | Default | Energy-Aware | Δ% | > 1σ? |
|:---|:---:|:---:|:---:|:---:|
| Total estimated power (W) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Scheduling delay (s) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Utilisation spread (pct-pts) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

**Interpretation:** At high load the 80% utilisation guard becomes active on
saturated nodes, restricting placement. Both schedulers may produce similar
power if the guard forces them to the same nodes.

---

### Scenario 4 — Mixed Workload (3 nginx + 3 stress-ng; has p95 latency data)

| Metric | Default | Energy-Aware | Δ% | > 1σ? |
|:---|:---:|:---:|:---:|:---:|
| Total estimated power (W) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| p95 HTTP latency (ms) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Scheduling delay (s) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| Utilisation spread (pct-pts) | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

**Placement:** `[CSV: scenario4 placement columns for both schedulers]`

**Load test conditions:** fortio, 50 QPS, 4 concurrent connections, 60 seconds.
Stress-ng batch pods (`--cpu 1 --cpu-load 20`) were running concurrently during
the load test, creating CPU interference.

**Interpretation:** The p95 latency figures reflect the combined effect of
scheduler placement and in-cluster network latency on a Kind-on-Docker setup.
Values should be read as relative comparisons, not absolute production latency.

---

## 2. Where It Did Not Help

The following scenarios or metrics showed the energy-aware scheduler as
**equal to or worse than** the default scheduler:

> **All explanations below are hypotheses, not findings.**
> Findings would require larger sample sizes and isolated hardware.

| Scenario | Metric | Default | Energy-Aware | Hypothesis |
|:---|:---|:---:|:---:|:---|
| Scenario 1 | Total estimated power | `[CSV]` | `[CSV]` | *Hypothesis:* At near-zero utilisation, all nodes receive nearly equal `L_i` and `P_i` scores. The `R_i` term dominates, and the default scheduler may happen to pick the same nodes. The simulated power difference is a function of idle wattage only and is constant regardless of placement. |
| Scenario 2 | Total estimated power (if EA > Default) | `[CSV]` | `[CSV]` | *Hypothesis:* Concentrating pods onto efficient nodes increases those nodes' utilisation, which raises their estimated power. The linear model treats idle power as a floor — if the efficient node's utilisation rises sufficiently, its total `P(u)` can exceed a lightly-used power-hungry node's `P_idle`. |
| All scenarios | Scheduling delay | `[CSV]` | `[CSV]` | *Hypothesis:* The Prometheus query (even with 5 s TTL cache) adds measurable latency to each scheduling cycle. On a low-traffic cluster the default scheduler completes faster because it does not make any external calls. |
| Scenario 4 | p95 latency (if EA ≥ Default) | `[CSV]` | `[CSV]` | *Hypothesis:* Kind-on-Docker network latency is dominated by the loopback stack and host Linux scheduler jitter, not by which Kubernetes node the pod lands on. In this environment the placement decision has little effect on application latency. |

---

## 3. Threats to Validity

1. **Simulated power — not measured.**  
   All power figures are produced by the formula `P(u) = P_idle + (P_max − P_idle) × u`
   applied to CPU utilisation from node-exporter. `P_idle` and `P_max` are
   Kubernetes node labels set by `scripts/label-nodes.sh`. There are no
   physical power sensors. The values are illustrative, not empirical.

2. **Containers sharing one host kernel.**  
   All three "worker nodes" and the control plane are Docker containers on the
   same host machine (Windows 11 + WSL2). CPU utilisation is measured at the
   cgroup level. Inter-node interference, scheduling jitter, and noisy-neighbour
   effects from the host OS cannot be controlled or quantified.

3. **Small sample size.**  
   Five runs per scenario/scheduler combination produce a standard deviation
   estimate but are insufficient for rigorous statistical significance testing
   (Mann–Whitney U at α = 0.05 requires substantially more samples). The
   `larger_than_std` flag in `deltas.csv` is a weak, informal indicator only.

4. **Single tuned weight set.**  
   Weights were selected by a grid search with 6 combinations from
   `{0.2, 0.4, 0.6}³`. A finer grid or Bayesian optimisation (documented as
   future work in `docs/week6-notes.md`) might find a better trade-off. The
   reported results are for one specific weight configuration.

5. **Synthetic workloads.**  
   nginx (latency-sensitive) and stress-ng (batch) are artificial stand-ins.
   Real datacenter workloads (database queries, ML training, microservices)
   have different resource access patterns, inter-pod communication, and
   I/O characteristics that may lead to very different scheduling decisions.
