# docs/contribution.md — Attribution and Contribution

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**

This document lists every file in the repository and its origin.

---

## Original Work (This Project)

The following files are entirely original to this B.Tech project and were
not copied or adapted from any upstream repository:

| Path | Description |
|:---|:---|
| `scheduler/scheduler-plugins/pkg/energyaware/energy_aware.go` | Plugin struct, `Score()`, `NormalizeScore()`, `New()` |
| `scheduler/scheduler-plugins/pkg/energyaware/scoring.go` | `computeRi()`, `computeLi()`, `computePi()`, `combineScore()` |
| `scheduler/scheduler-plugins/pkg/energyaware/args.go` | `EnergyAwareArgs`, `WeightProfile`, `defaultArgs()` |
| `scheduler/scheduler-plugins/pkg/energyaware/prometheus.go` | `PrometheusClient` with 5 s TTL cache |
| `scheduler/manifests/configmap.yaml` | `KubeSchedulerConfiguration` with plugin args |
| `scheduler/manifests/deployment.yaml` | `energy-aware-scheduler` Deployment |
| `scheduler/manifests/rbac.yaml` | RBAC for the scheduler |
| `scheduler/manifests/serviceaccount.yaml` | ServiceAccount |
| `monitoring/values.yaml` | kube-prometheus-stack Helm values |
| `monitoring/dashboards/scheduler-comparison.json` | Grafana comparison dashboard |
| `monitoring/dashboards/dashboard-configmap.yaml` | Grafana dashboard ConfigMap template |
| `cluster/kind-config.yaml` | KIND cluster definition |
| `workloads/*.yaml` | nginx, stress-ng, fortio workload manifests |
| `workloads/scenarios/*.yaml` | Per-scenario manifests for Scenarios 1–4 |
| `scripts/setup-cluster.sh` | Cluster creation script |
| `scripts/teardown.sh` | Cluster deletion script |
| `scripts/label-nodes.sh` | Node power-profile labelling |
| `scripts/install-monitoring.sh` | Helm install of kube-prometheus-stack |
| `scripts/build-scheduler.sh` | Scheduler image build and KIND load |
| `scripts/deploy-scheduler.sh` | Apply scheduler manifests |
| `scripts/run-experiments.sh` | Automated experiment runner |
| `scripts/analyze_results.py` | Results aggregation and chart generation |
| `scripts/tune_weights.py` | Weight grid search |
| `scripts/compute_deltas.py` | Percent-change delta computation |
| `scripts/run-all.sh` | Master pipeline script |
| `scripts/demo.sh` | Demo runner |
| `scripts/port-forward.sh` | Port-forward helper |
| `scripts/compare-schedulers.sh` | Ad-hoc scheduler comparison helper |
| `scripts/requirements.txt` | Python package list |
| `docs/` (all `.md` files) | All project documentation |
| `results/` (all CSVs and charts) | All experiment outputs |

---

## Forked / Upstream Code

### kubernetes-sigs/scheduler-plugins

The directory `scheduler/scheduler-plugins/` is a fork (or clone) of
[kubernetes-sigs/scheduler-plugins](https://github.com/kubernetes-sigs/scheduler-plugins),
licensed under the **Apache License 2.0**.

- The original `LICENSE` file is preserved at
  `scheduler/scheduler-plugins/LICENSE`.
- All upstream files outside `pkg/energyaware/` remain unmodified.
- The `pkg/energyaware/` sub-package is entirely original to this project
  (see above).

### PEAKS — Power and Energy Aware Kubernetes Scheduler

[sustainable-computing-io/peaks](https://github.com/sustainable-computing-io/peaks)
was studied as the primary reference implementation for energy-aware scheduling
in Kubernetes. **No PEAKS code appears in this repository.**  
PEAKS was evaluated and excluded due to its hard dependency on Kepler metrics
unavailable in the KIND environment (documented in `docs/peaks-setup.md`).

### Kepler — Kubernetes-based Efficient Power Level Exporter

[sustainable-computing-io/kepler](https://github.com/sustainable-computing-io/kepler)
was evaluated as the energy-measurement backend. **No Kepler code appears in
this repository.** Kepler was ruled out on KIND/WSL2 because it requires
RAPL/eBPF hardware counters not available inside Docker-based nodes.

### Trimaran / TargetLoadPacking

The `TargetLoadPacking` plugin from
[kubernetes-sigs/scheduler-plugins/tree/master/pkg/trimaran](https://github.com/kubernetes-sigs/scheduler-plugins/tree/master/pkg/trimaran)
was considered as an additional baseline but was **not deployed** in this
evaluation (see `docs/trimaran-attempt.md`).

---

## NOTICE

This project is a B.Tech final-year project. It incorporates the
kubernetes-sigs/scheduler-plugins framework under the Apache License 2.0.
The EnergyAware plugin (`pkg/energyaware/`) is original work by the project
author. PEAKS and Kepler are cited as related work and reference
implementations; no code from those projects is reproduced here.
