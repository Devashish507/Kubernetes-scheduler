# Week 6 Results Narrative Draft

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> **Evaluation Scope**: Scenarios 1–4, Default Scheduler and Energy-Aware Scheduler,
> 5 runs each (40 total), Week 6 tuned weights.  
> **Data Source**: `results/week6/summary.csv` and `results/week6/tuning.csv`
>
> **Note:** This draft will be updated with exact numbers once the 40-run campaign
> completes.  All numeric placeholders are marked `[RUN]` and must be replaced
> with values directly from the CSV files.  Do not fabricate or round generously.

---

## 1. Executive Summary & Experimental Setup

Week 6 extended the Week 5 evaluation with three key improvements: weights were
tuned by a grid search, application (HTTP) latency was measured for Scenario 4
using a fortio load generator, and the run count was increased from 3 to 5 per
scheduler/scenario combination to reduce variance.

**Cluster**: 1 control-plane + 3 labeled worker nodes on Kind.
- `energy-worker` (efficient): p-idle = 20 W, p-max = 60 W
- `energy-worker2` (medium): p-idle = 40 W, p-max = 120 W
- `energy-worker3` (power-hungry): p-idle = 80 W, p-max = 200 W

All power values are simulated (see Limitations, §6).  PEAKS is excluded;
see `docs/peaks-setup.md`.

---

## 2. Weight Tuning Results

`scripts/tune_weights.py` evaluated [RUN] combinations (target: 6 per profile).
The selection rule: *lowest estimated power among combinations with p95 latency
within 10% of the best observed p95.*

| Combination | lat-wR | lat-wL | lat-wP | bat-wR | bat-wL | bat-wP | Power (W) | p95 (ms) | Status |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| *Values from tuning.csv — to be filled after run* | | | | | | | | | |

**Selected best combination**: [RUN from tuning.csv]  
Power = [RUN] W, p95 = [RUN] ms.  Applied to `scheduler/manifests/configmap.yaml`.

The scatter plot `results/week6/charts/weight_sensitivity.png` shows the
power vs p95 trade-off across all combinations.  The selected point sits in
the lower-left region, confirming that a meaningful power saving is achievable
without degrading p95 beyond the 10% tolerance.

---

## 3. Quantitative Summary (Week 6)

*Values are mean ± 1 std-dev across 5 runs.  Failed runs are excluded and counted.*

| Scenario | Scheduler | Power μ (W) ± σ | Delay μ (s) ± σ | p95 μ (ms) ± σ | Spread μ ± σ | Valid/Failed |
|:---|:---|:---|:---|:---|:---|:---|
| Scenario 1 | Default | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 1 | Energy-Aware | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 2 | Default | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 2 | Energy-Aware | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 3 | Default | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 3 | Energy-Aware | [RUN] ± [RUN] | [RUN] ± [RUN] | N/A | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 4 | Default | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN]/[RUN] |
| Scenario 4 | Energy-Aware | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN] ± [RUN] | [RUN]/[RUN] |

---

## 4. Findings by Metric

### 4.1 Estimated Cluster Power

*[To be written after runs complete. Use values from summary.csv column
`mean_total_power_W` and `std_total_power_W`. Write 2–3 plain sentences per
scenario, e.g.:  "In Scenario 3, the energy-aware scheduler estimated [X] W
(± [Y] W) versus [A] W (± [B] W) for the default scheduler, a [D]% reduction."]*

### 4.2 Scheduling Delay

*[To be written after runs complete. Cite values from `mean_scheduling_delay_s`
and `std_scheduling_delay_s`. Example sentence: "Mean scheduling delay under the
energy-aware scheduler was [X] s (± [Y] s) compared to [A] s (± [B] s) for the
default scheduler across all scenarios."]*

### 4.3 p95 Application Latency (Scenario 4)

*[To be written after runs complete. Values from `mean_p95_latency_ms` and
`std_p95_latency_ms` for scenario4 rows. Example: "The energy-aware scheduler
achieved a p95 HTTP response latency of [X] ms (± [Y] ms) during the 60-second
fortio load test (50 QPS, 4 connections), compared to [A] ms (± [B] ms) for
the default scheduler. Batch stress-ng pods were running concurrently."]*

### 4.4 Utilisation Spread (Scenario 4)

*[To be written after runs complete. Values from `mean_util_spread_pct`.]*

---

## 5. Chart Descriptions

### 5.1 Power by Scenario (`charts/power_by_scenario.png`)

*[2–3 sentences after run, e.g.: "The chart shows grouped bars for total
estimated cluster power per scenario. The energy-aware scheduler reduces power
in Scenarios [X] and [Y]. In Scenario [Z] it uses more power because …"]*

### 5.2 Scheduling Latency by Scenario (`charts/latency_by_scenario.png`)

*[2–3 sentences.]*

### 5.3 Scenario 4 Utilisation Spread (`charts/utilization_scenario4.png`)

*[2–3 sentences.]*

### 5.4 p95 Latency, Scenario 4 (`charts/p95_latency_scenario4.png`)

*[2–3 sentences.]*

### 5.5 Weight Sensitivity Scatter (`charts/weight_sensitivity.png`)

*[2–3 sentences describing the power-vs-latency trade-off visible in the
scatter and which combination was selected.]*

---

## 6. Limitations

1. **Power is simulated.** KIND has no real power sensors. Kepler was evaluated
   and ruled out (see `docs/peaks-setup.md`): it requires RAPL/eBPF hardware
   counters unavailable inside Docker-based KIND nodes. All power figures in
   this report are mathematical estimates derived from a linear model and
   synthetic labels — they are not physical wattage measurements.

2. **Nodes are containers on one host.** All three "worker nodes" are Docker
   containers sharing the same host kernel and CPU. CPU utilisation measurements
   reflect container-level cgroup accounting, not isolated physical cores. This
   means interference between workers is not independently controllable, and
   reported utilisation values are noisy due to the shared scheduler and memory
   subsystem.

3. **Small sample size.** Each scenario/scheduler combination uses 5 runs. Five
   samples are sufficient for reporting mean and standard deviation, but not for
   robust statistical significance testing (e.g., Mann–Whitney U tests would need
   larger samples). Standard deviations in summary.csv reflect real measurement
   noise, not theoretical confidence intervals.

4. **PEAKS excluded.** The PEAKS scheduler baseline could not be included because
   it hard-depends on Kepler metrics (`kepler_node_package_joules_total`,
   `kepler_node_dram_joules_total`) which are unavailable in this environment.

5. **Energy-aware scheduler not clearly better in all scenarios.** Based on
   Week 5 data, the energy-aware scheduler used *more* estimated power in
   Scenarios 1 and 2 compared to the default scheduler. This occurs because,
   at low utilisation, the additional Prometheus query overhead can shift
   placement onto nodes with slightly higher base utilisation, increasing the
   linear power estimate. The project reports this directly and does not claim
   universal superiority. Week 6 re-runs with tuned weights may change this
   outcome; the narrative will be updated with actual numbers.

6. **Application latency noise.** HTTP latency measured by fortio on a
   Kind-on-Docker cluster is affected by the loopback network stack and Linux
   scheduler jitter. Values are useful for relative comparison between schedulers
   but should not be interpreted as production latency figures.
