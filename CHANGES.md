


# Project Changes & Chronology

> **B.Tech Final-Year Project: Energy-Aware Kubernetes Scheduler**  
> For detailed file-by-file attribution and license boundaries, refer to [docs/contribution.md](docs/contribution.md).

---

## Weekly Progression Summary

### Week 1: Project Setup & Baseline Cluster
- Configured 4-node Kind cluster `energy` (1 control-plane, 3 worker nodes: `energy-worker`, `energy-worker2`, `energy-worker3`).
- Set up local cluster manifests in `cluster/kind-config.yaml`.
- Automated cluster lifecycle scripts (`scripts/setup-cluster.sh`, `scripts/teardown.sh`).

### Week 2: Monitoring & Telemetry Infrastructure
- Deployed `kube-prometheus-stack` (v91.5.2) with Prometheus, Alertmanager, and Node Exporter.
- Configured custom Grafana dashboard in `monitoring/dashboards/scheduler-comparison.json`.
- Explored Kepler power estimation and documented hardware counter/RAPL constraints on Kind.

### Week 3: Synthetic Power Model
- Formulated linear node power consumption model:
  $$P_i(u_i) = P_{\text{idle},i} + u_i \cdot (P_{\text{max},i} - P_{\text{idle},i})$$
- Configured heterogeneous node profiles via Kubernetes labels:
  - `energy-worker` (efficient): $P_{\text{idle}} = 20\text{ W}, P_{\text{max}} = 60\text{ W}$
  - `energy-worker2` (medium): $P_{\text{idle}} = 40\text{ W}, P_{\text{max}} = 120\text{ W}$
  - `energy-worker3` (power-hungry): $P_{\text{idle}} = 80\text{ W}, P_{\text{max}} = 200\text{ W}$
- Created `scripts/label-nodes.sh` to attach metadata labels.

### Week 4: EnergyAware Scheduler Plugin Development
- Forked `kubernetes-sigs/scheduler-plugins` (Apache 2.0).
- Implemented `EnergyAware` scheduling plugin in `scheduler/scheduler-plugins/pkg/energyaware/`:
  - `plugin.go`: Core Score plugin interface implementation.
  - `scoring.go`: Node scoring arithmetic: $\text{Score}_i = w_R \cdot R_i + w_L \cdot L_i - w_P \cdot P_i$.
  - `prometheus.go`: Client querying live node CPU utilisation.
- Configured 80% node utilisation safety guard to prevent hot-spotting.
- Implemented two profile types: `latency-sensitive` and `batch` via pod annotations.
- Created deployment manifests: ConfigMap, Deployment, ServiceAccount, and RBAC rules under `scheduler/manifests/`.

### Week 5: Experiment Automation & Baseline Evaluation
- Implemented `workloads/scenarios/` covering Scenarios 1–4 from evaluation design.
- Built automated benchmarking harness `scripts/run-experiments.sh`.
- Created result aggregation and charting script `scripts/analyze_results.py`.
- Conducted initial 3-run evaluations comparing Default Scheduler vs EnergyAware Scheduler.

### Week 6: Rigorous Experimentation & Weight Tuning
- Implemented systematic grid search script `scripts/tune_weights.py`.
- Integrated HTTP application latency measurement using `fortio` (`workloads/load-generator.yaml`).
- Upgraded experiment pipeline to 5 runs per scenario/scheduler combination (40 runs total) with mean and standard deviation reporting.
- Evaluated PEAKS compatibility (`docs/peaks-setup.md`).

### Week 7: Analysis, Reproducibility & Paper/Demo Preparation
- Created `scripts/compute_deltas.py` for mathematical percentage difference computation (`results/week7/deltas.csv`).
- Created one-shot master pipeline script `scripts/run-all.sh`.
- Created interactive demo runner `scripts/demo.sh` and fallback assets guide `docs/demo-fallback.md`.
- Authored final analysis document `docs/final-analysis.md` with explicit "Where it did not help" and "Threats to validity" sections.
- Documented evaluation of Trimaran baseline plugin (`docs/trimaran-attempt.md`).
- Prepared paper drafts (`docs/paper-implementation-section.md`, `docs/paper-results-section.md`, `docs/paper-edits.md`, `docs/paper-figures.md`).
- Documented 15 comprehensive viva questions and answers (`docs/viva-questions.md`).
- Pinned environment and dependency versions (`docs/environment.md`, `scripts/requirements.txt`).
- Archived exploratory files and organized workspace.

---

## File Provenance & Attribution

See [docs/contribution.md](docs/contribution.md) for full breakdown:
- **Upstream / Forked**: `scheduler/scheduler-plugins/` (excluding `pkg/energyaware/`), licensed under Apache 2.0.
- **Original Work**: `scheduler/scheduler-plugins/pkg/energyaware/`, all Kubernetes manifests in `scheduler/manifests/`, `cluster/`, and `workloads/`, all scripts in `scripts/`, all documentation in `docs/`, and Grafana dashboards in `monitoring/`.
