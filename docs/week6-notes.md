# Week 6 Notes

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**

---

## 1. Weight Tuning Approach and Future Work

The Week 6 grid search (`scripts/tune_weights.py`) evaluates all valid
`(wR, wL, wP)` triples from the set `{0.2, 0.4, 0.6}` that sum to 1.0, giving
6 combinations per profile.  The best combination is selected by the rule:

> *Among all combinations with p95 latency within 10% of the lowest observed
> p95, choose the one with the lowest total estimated cluster power.*

**Bayesian optimization of weights is future work.**  The grid search is the
simpler stand-in that is feasible within the project timeline.  A Bayesian
approach (e.g., using Gaussian Process regression over the `(wR, wL, wP)`
space with an acquisition function such as Expected Improvement) would find
the Pareto-optimal frontier of power vs latency more efficiently and without
the exhaustive enumeration that limits the grid to a small value set.
References: Snoek et al., "Practical Bayesian Optimization of Machine Learning
Algorithms," NeurIPS 2012; Shahriari et al., IEEE Proc. 2016.

---

## 2. Dashboard Panels — Paper and Presentation Screenshot Candidates

The following panels from `monitoring/dashboards/scheduler-comparison.json`
are recommended for inclusion in the paper (Section 5.x) and the presentation:

| Panel ID | Panel Title | Why it is useful |
|:---:|:---|:---|
| **4** | Estimated Node Power (W) — Simulated (timeseries) | Shows how power tracks CPU utilisation over time for each node; illustrates the heterogeneous profile. |
| **5** | Total Estimated Cluster Power (W) (stat) | Single-number comparison between runs; easy to read on a slide. |
| **12** | Per-Node Estimated Power — Current (W) (stat/gauge) | Colour-coded gauges make the efficient vs power-hungry contrast immediately visible. **Recommended cover screenshot.** |
| **2** | Per-Node CPU Utilization (%) (timeseries) | Shows the utilisation spread the scheduler produces across nodes. |
| **7** | Pods per Node (donut chart) | Visually contrasts how many pods each scheduler places on each node. |
| **13** | Pods per Node by Scheduler (timeseries) | Separates placement by scheduler label — useful when both schedulers are running in parallel. |
| **8** | Pod → Node Placement table | Provides detailed per-pod evidence for scheduling decisions. |

> **Note on panel 13 ("Pods per Node by Scheduler"):**  
> The PromQL query joins `kube_pod_info` with `kube_pod_labels` using the
> `energy.project/scheduler` label.  This requires kube-state-metrics to be
> configured with `--metric-labels-allowlist=pods=[energy.project/scheduler]`
> (or equivalent).  If the label does not appear, filter by pod-name prefix
> as an alternative.  The metric `kube_pod_labels` was verified to exist in
> the kube-prometheus-stack 45.x deployment used in this cluster.

---

## 3. Metric and Label Name Verification

The following metric and label names were verified against the running
Prometheus instance before use in the dashboard and scripts:

| Metric / Label | Source | Verified via |
|:---|:---|:---|
| `node_cpu_seconds_total{mode="idle"}` | node-exporter | `prometheous_queries.txt` + manual port-forward |
| `node_uname_info` (label: `nodename`) | node-exporter | `prometheous_queries.txt` |
| `kube_pod_info` (labels: `pod`, `node`, `namespace`) | kube-state-metrics | docs/metrics.md |
| `kube_pod_labels` | kube-state-metrics | docs/metrics.md |
| `kube_node_status_allocatable` | kube-state-metrics | docs/metrics.md |
| `kube_pod_container_resource_requests` | kube-state-metrics | docs/metrics.md |
| `energy.project/p-idle`, `energy.project/p-max` | node labels | `scripts/label-nodes.sh` |

**Uncertainty:** The `kube_pod_labels` metric exposes custom pod labels only
when kube-state-metrics is configured with the label allowlist.  The dashboard
panel 13 description documents this gap.  Power is also computed offline in
`analyze_results.py` using the same formula, which is the authoritative source
for paper results.
