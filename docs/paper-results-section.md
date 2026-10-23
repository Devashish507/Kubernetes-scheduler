# Paper Draft — Results Section

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> This is a draft of the Results section.  
> All `[CSV: ...]` placeholders must be replaced with the exact values from
> `results/week6/summary.csv` and `results/week7/deltas.csv` before submission.  
> Do not round or estimate — copy numbers directly from the CSVs.  
> Written in past tense.

---

## 5. Results

### 5.1 Pod Placement

Figure 1 (`results/week6/charts/utilization_scenario4.png`) shows the
per-node CPU utilisation spread under both schedulers for Scenario 4.

Under the default scheduler, pods were distributed evenly across the three
worker nodes, with `[CSV: scenario4/default placements_energy_worker_eff]`,
`[CSV: scenario4/default placements_energy_worker2_med]`, and
`[CSV: scenario4/default placements_energy_worker3_pwr]` pods placed on
the efficient, medium, and power-hungry nodes respectively (mean over 5 runs).

Under the energy-aware scheduler, the distribution was
`[CSV: scenario4/ea placements_energy_worker_eff]` /
`[CSV: scenario4/ea placements_energy_worker2_med]` /
`[CSV: scenario4/ea placements_energy_worker3_pwr]` pods.

In Scenario 1 (low load), the energy-aware scheduler placed
`[CSV]` pods on the power-hungry node compared to `[CSV]` for the default
scheduler. In Scenario 2, `[CSV]` pods were placed on `energy-worker3` by
the energy-aware scheduler versus `[CSV]` for the default.

### 5.2 Estimated Cluster Power

Figure 2 (`results/week6/charts/power_by_scenario.png`) shows the total
estimated cluster power (W) for both schedulers across all four scenarios,
with error bars representing one standard deviation over 5 runs.

Estimated power is computed as:
$$\hat{P}_{\text{cluster}} = \sum_{i \in \text{workers}} \bigl[P_{\text{idle},i} + u_i \cdot (P_{\text{max},i} - P_{\text{idle},i})\bigr]$$

where $u_i$ is the Prometheus-measured CPU utilisation fraction at the end
of the stabilisation window.

| Scenario | Default (W) | σ | Energy-Aware (W) | σ | Δ% |
|:---|:---:|:---:|:---:|:---:|:---:|
| 1 — Low | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 2 — Medium | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 3 — High | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 4 — Mixed | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

Values are means over 5 independent runs. Δ% is from `results/week7/deltas.csv`.

### 5.3 Node Utilisation Spread

The utilisation spread (maximum − minimum node utilisation, in percentage
points) indicates how evenly the scheduler distributed load. A lower spread
suggests more even distribution; a higher spread (combined with lower power)
suggests intentional concentration on efficient nodes.

| Scenario | Default spread (pct-pts) | σ | Energy-Aware spread (pct-pts) | σ |
|:---|:---:|:---:|:---:|:---:|
| 1 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 2 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 3 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 4 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

### 5.4 Application Latency (Scenario 4)

Figure 3 (`results/week6/charts/p95_latency_scenario4.png`) compares the
p95 HTTP response latency measured by the fortio load generator (50 QPS,
4 concurrent connections, 60 s) under both schedulers for Scenario 4.

The load test was run while the batch stress-ng pods were Running concurrently,
creating CPU interference that representative of a real mixed-workload environment.

| Scheduler | p95 latency (ms) | σ |
|:---|:---:|:---:|
| Default | `[CSV: scenario4/default mean_p95_latency_ms]` | `[CSV: scenario4/default std_p95_latency_ms]` |
| Energy-Aware | `[CSV: scenario4/ea mean_p95_latency_ms]` | `[CSV: scenario4/ea std_p95_latency_ms]` |

The weight tuning process targeted a p95 latency within 10% of the minimum
observed p95 while minimising estimated power. The selected combination
achieved p95 = `[CSV: tuning.csv selected row p95_latency_ms]` ms.
Full tuning results are shown in Figure 4
(`results/week6/charts/weight_sensitivity.png`).

### 5.5 Scheduling Overhead

Figure 5 (`results/week6/charts/latency_by_scenario.png`) compares the mean
scheduling delay (time from pod creation to PodScheduled condition) across
scenarios and schedulers.

| Scenario | Default delay (s) | σ | Energy-Aware delay (s) | σ |
|:---|:---:|:---:|:---:|:---:|
| 1 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 2 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 3 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |
| 4 | `[CSV]` | `[CSV]` | `[CSV]` | `[CSV]` |

The energy-aware scheduler incurred additional scheduling overhead due to
Prometheus queries at scheduling time. The 5-second TTL cache
(`prometheus.go`) mitigated repeated queries within a burst of simultaneous
pod creations. All measured delays remained sub-second.

### 5.6 Discussion

The results showed that the energy-aware scheduler [modified/did not consistently
modify] pod placement toward the efficient node (`energy-worker`). Where
differences were observed, the `larger_than_std` column in
`results/week7/deltas.csv` indicates whether the change exceeded one standard
deviation and can therefore be distinguished from measurement noise.

The estimated power differences between schedulers were small in absolute terms
because the Kind environment constrains CPU utilisation to low levels (typically
< 10%) for the test workloads; at low utilisation, all nodes' linear power
estimates converge toward their idle values, reducing the effective range of
the $P_i$ scoring term.

Application latency was dominated by the Kind-on-Docker network stack rather
than scheduler placement, as all nodes share the same host loopback interface.
Latency figures should be interpreted as relative comparisons between schedulers
under identical conditions, not as absolute application performance predictions.

All power figures are estimates derived from a simulated linear model. No
physical energy measurements were obtained.
