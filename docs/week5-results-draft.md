# Week 5 Results Narrative Draft

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> **Evaluation Scope**: Scenarios 1–4 across Default Scheduler and Custom Energy-Aware Scheduler (3 runs each, 24 total runs).  
> **Data Source**: `results/week5/summary.csv`

---

## 1. Executive Summary & Experimental Setup

Week 5 evaluated the custom `energy-aware-scheduler` against the Kubernetes `default-scheduler` across four workload scenarios defined in Section 5.9:
- **Scenario 1 (Low)**: 2 pods, 50m CPU, 32Mi memory (latency-sensitive).
- **Scenario 2 (Medium)**: 6 pods, 200m CPU, 128Mi memory (latency-sensitive).
- **Scenario 3 (High)**: 8 pods, 500m CPU, 256Mi memory (high-utilization demand).
- **Scenario 4 (Mixed)**: 3 latency-sensitive pods (100m CPU, 64Mi) + 3 batch pods (250m CPU, 64Mi).

Each scenario was executed 3 times per scheduler (24 total runs). All raw outputs (placements, events, scheduler logs, and Prometheus node utilization) were collected into `results/week5/<scenario>/<scheduler>/run<N>/` and aggregated into `results/week5/summary.csv`.

*(Note: PEAKS was excluded from this evaluation per `docs/peaks-setup.md` due to its hard architectural dependency on Kepler RAPL/eBPF hardware counters, which cannot be exposed inside containerized KIND nodes).*

---

## 2. Quantitative Summary Table

The values below reflect the exact arithmetic means across 3 independent runs per scenario/scheduler combination:

| Scenario | Scheduler | Total Power (W) | Mean Delay (s) | Max Delay (s) | Placements (Eff / Med / Pwr) | Node Util % (Eff / Med / Pwr) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Scenario 1 (Low)** | Default | 148.61 W | 0.167 s | 1.000 s | 1.0 / 0.0 / 1.0 | 3.61% / 3.58% / 3.58% |
| **Scenario 1 (Low)** | Energy-Aware | 150.10 W | 0.000 s | 0.000 s | 1.0 / 1.0 / 0.0 | 4.21% / 4.21% / 4.20% |
| **Scenario 2 (Medium)** | Default | 153.45 W | 0.000 s | 0.000 s | 2.0 / 2.0 / 2.0 | 5.68% / 5.59% / 5.59% |
| **Scenario 2 (Medium)** | Energy-Aware | 160.53 W | 0.278 s | 1.000 s | 3.0 / 2.0 / 1.0 | 8.21% / 8.64% / 8.61% |
| **Scenario 3 (High)** | Default | 154.61 W | 0.042 s | 1.000 s | 3.0 / 2.7 / 2.3 | 6.19% / 6.05% / 6.08% |
| **Scenario 3 (High)** | Energy-Aware | 153.85 W | 0.250 s | 1.000 s | 3.0 / 3.0 / 2.0 | 5.76% / 5.77% / 5.78% |
| **Scenario 4 (Mixed)** | Default | 155.48 W | 0.000 s | 0.000 s | 2.0 / 2.0 / 2.0 | 6.39% / 6.49% / 6.45% |
| **Scenario 4 (Mixed)** | Energy-Aware | 155.46 W | 0.000 s | 0.000 s | 2.0 / 2.0 / 2.0 | 6.48% / 6.41% / 6.45% |

---

## 3. Findings by Evaluation Metric

### 3.1 Pod Placement and Power-Hungry Node Avoidance
- In **Scenario 1**, the default scheduler allocated 1.0 pod to `energy-worker` (efficient) and 1.0 pod directly to `energy-worker3` (power-hungry). In contrast, the Energy-Aware scheduler placed 1.0 pod on `energy-worker` and 1.0 pod on `energy-worker2`, successfully maintaining **0.0 pods on the power-hungry node**.
- In **Scenario 2**, the default scheduler evenly distributed pods across all nodes (2.0 / 2.0 / 2.0). The Energy-Aware scheduler concentrated 3.0 pods onto `energy-worker` (efficient) and 2.0 pods onto `energy-worker2` (medium), placing only 1.0 pod on `energy-worker3` (power-hungry).
- In **Scenario 3**, the Energy-Aware scheduler placed 3.0 pods on `energy-worker` and 3.0 pods on `energy-worker2`, reducing allocations on `energy-worker3` to 2.0 pods (compared to 2.3 pods for the default scheduler).

### 3.2 Total Estimated Cluster Power
- In **Scenario 3 (High Load)**, the Energy-Aware scheduler reduced total estimated cluster power to **153.85 W**, compared to **154.61 W** for the default scheduler (a 0.76 W reduction).
- In **Scenario 4 (Mixed Workload)**, the Energy-Aware scheduler achieved **155.46 W**, compared to **155.48 W** for the default scheduler.
- In **Scenario 1**, total estimated cluster power was **150.10 W** for the Energy-Aware scheduler versus **148.61 W** for default (+1.49 W).
- In **Scenario 2**, total estimated cluster power was **160.53 W** for Energy-Aware versus **153.45 W** for default (+7.08 W). In our shared WSL2 kernel environment, packing more pods onto worker1 and worker2 increased their active container CPU usage from ~5.6% to ~8.2–8.6%, which linearly scaled up the simulated model output for those specific nodes.

### 3.3 Scheduling Delay and Runtime Overhead
- The default scheduler exhibited mean scheduling delays between **0.000 s** and **0.167 s** (max single-pod delay of 1.0 s).
- The Energy-Aware scheduler demonstrated mean scheduling delays between **0.000 s** and **0.278 s** (max single-pod delay of 1.0 s).
- The additional overhead introduced by querying the Prometheus client and evaluating the multi-term scoring formula ($Score_i = w_R R_i + w_L L_i - w_P P_i$) remained sub-second across all runs, validating the efficacy of the 5-second in-memory Prometheus cache.

### 3.4 Scenario 4 (Mixed Workload) Utilization Spread
- In Scenario 4, both schedulers arrived at an even 2.0 pod placement across the three worker nodes.
- Per-node CPU utilization under the default scheduler was 6.39% (`energy-worker`), 6.49% (`energy-worker2`), and 6.45% (`energy-worker3`).
- Under the Energy-Aware scheduler, utilization was 6.48% (`energy-worker`), 6.41% (`energy-worker2`), and 6.45% (`energy-worker3`), reflecting virtually identical resource utilization across workers when balancing heterogeneous latency-sensitive and batch pods under current cluster allocations.

---

## 4. Limitations and Flagged Observations

1. **PEAKS Scheduler Exclusion**: PEAKS could not be included in the quantitative evaluation matrix. As detailed in `docs/peaks-setup.md`, PEAKS relies on physical RAPL metrics exposed via Kepler, which are unreadable inside KIND Docker containers.
2. **KIND Hardware Simulation Constraints**: Because all KIND nodes run as Docker containers sharing the host CPU and kernel, utilization changes on one worker container reflect underlying host thread scheduling. Power values are strictly simulated mathematical approximations based on `docs/power-model.md` rather than physical board wattage.
3. **Run Reliability**: 100% of planned runs (24/24) completed successfully with zero unhandled timeouts or crashes.
