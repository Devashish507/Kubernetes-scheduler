# Paper Draft — Implementation Section

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> This is a draft of the Implementation / Experimental Setup section of the paper.
> All numeric references are placeholders `[CSV]` to be filled from the CSV files.
> Written in past tense. Uses the notation from the paper.

---

## 4. Implementation

### 4.1 Experimental Environment

The evaluation was conducted on a local Kubernetes cluster provisioned using
Kind (Kubernetes-in-Docker) on a Windows 11 host with WSL2 and Docker Desktop.
The cluster comprised one control-plane node and three worker nodes, each
running as a Docker container. Table 1 summarises the simulated power profiles
applied to the worker nodes.

**Table 1. Simulated Node Power Profiles**

| Node | Profile Tier | P_idle (W) | P_max (W) | idle/max ratio |
|:---|:---|:---:|:---:|:---:|
| energy-worker | efficient | 20 | 60 | 0.33 |
| energy-worker2 | medium | 40 | 120 | 0.33 |
| energy-worker3 | power-hungry | 80 | 200 | 0.40 |

The profiles were chosen to reflect the idle-to-peak power ratios reported in
SPECpower_ssj2008 submissions for efficiency-class, mid-range, and
workstation-class servers respectively. The values were applied as Kubernetes
node labels (`energy.project/p-idle` and `energy.project/p-max`) and read by
the scheduler plugin at runtime. All power values are simulated; the Kind
environment provides no hardware power sensors.

Cluster monitoring was provided by `kube-prometheus-stack` version 91.5.2
(Prometheus, Grafana, node-exporter, kube-state-metrics), deployed via Helm.
Node CPU utilisation was queried from Prometheus using the standard
node-exporter metric `node_cpu_seconds_total`.

### 4.2 Plugin Implementation

The EnergyAware scheduler was implemented as a Kubernetes Scheduler Framework
plugin using the `kubernetes-sigs/scheduler-plugins` project as the build
scaffold. The plugin registered the `Score` and `NormalizeScore` extension
points. No changes were made to upstream scheduler-plugins code outside the
`pkg/energyaware/` package.

**Scoring formula.** Each candidate node *i* received a composite score:

$$\text{Score}_i = w_R \cdot R_i + w_L \cdot L_i - w_P \cdot P_i$$

where:

- $R_i \in [0, 1]$ is the resource-suitability term: the average fractional
  headroom remaining for CPU and memory after placing the pod.
- $L_i \in [0, 1]$ is the latency-suitability term: $1 - u_i / 100$, where
  $u_i$ is the node's current CPU utilisation. A fully idle node yields $L_i = 1$.
- $P_i \in [0, 1]$ is the normalised estimated power term:
  $P_i = P_{\text{idle},i} + u_{\text{after},i}(P_{\text{max},i} - P_{\text{idle},i})$,
  normalised by a cluster-wide reference of 200 W (the highest `p-max` label).
  Here $u_{\text{after},i}$ is the estimated utilisation after placing the pod.

**Utilisation guard.** Nodes with $u_i \geq 80\%$ received the minimum score
(MinNodeScore = 0) and were effectively excluded from placement. This hard
constraint prevented overloading any node regardless of its power profile.

**Weight profiles.** Two named weight profiles were configurable via the
`KubeSchedulerConfiguration` ConfigMap without rebuilding the image:

- *Latency-sensitive* (`energy.project/workload-type=latency-sensitive`):
  $w_R = 0.2$, $w_L = 0.6$, $w_P = 0.2$. The $L_i$ term dominated,
  preferring idle nodes.
- *Batch* (`energy.project/workload-type=batch`):
  $w_R = 0.2$, $w_L = 0.2$, $w_P = 0.6$. The $P_i$ term dominated,
  preferring energy-efficient nodes.

The reported weights are the result of a grid search over
$\{w_R, w_L, w_P\} \in \{0.2, 0.4, 0.6\}^3$ with $w_R + w_L + w_P = 1.0$.
The selected combination minimised estimated cluster power subject to p95
latency remaining within 10% of the best observed p95 across all combinations.
Full results are in `results/week6/tuning.csv`.

**Prometheus integration.** The plugin queried Prometheus at scheduling time
using the PromQL expression:
```
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
```
Query results were cached with a 5-second TTL to avoid stalling the scheduling
loop under concurrent pod creation.

**NormalizeScore.** Raw composite scores were linearly mapped to
$[1, 100]$ so that the best feasible node received 100 and the worst received 1.
Nodes that triggered the utilisation guard or lacked power labels received 0.

### 4.3 Baseline Schedulers

**Kubernetes Default Scheduler.** The built-in `default-scheduler` was used as
the primary baseline. It schedules pods based on resource availability, spreading
load across nodes using the `LeastAllocated` and `BalancedAllocation` plugins.
It makes no reference to energy or power profiles.

**PEAKS.** The PEAKS scheduler (sustainable-computing-io/peaks) was considered
as a literature baseline. PEAKS requires Kepler metrics
(`kepler_node_package_joules_total`, `kepler_node_dram_joules_total`) which
depend on Linux RAPL hardware counters accessible via eBPF. These counters are
unavailable inside Kind Docker nodes because all worker nodes share the host
kernel without isolated power domains. PEAKS was therefore excluded from the
quantitative evaluation.

**Trimaran (TargetLoadPacking).** The Trimaran `TargetLoadPacking` plugin from
`kubernetes-sigs/scheduler-plugins` was considered as a resource-efficiency
baseline. It was not deployed within the available time budget; see
`docs/trimaran-attempt.md` for details.

### 4.4 Test Workloads

Four workload scenarios were defined to span a range of cluster load levels:

| Scenario | Description | Replicas | CPU request | Memory request | Workload type |
|:---|:---|:---:|:---:|:---:|:---|
| 1 — Low | 2 latency-sensitive pods | 2 | 50m | 32Mi | latency-sensitive |
| 2 — Medium | 6 latency-sensitive pods | 6 | 200m | 128Mi | latency-sensitive |
| 3 — High | 8 mixed pods, high CPU | 8 | 500m | 256Mi | mixed |
| 4 — Mixed | 3 nginx + 3 stress-ng | 3+3 | 100m + 250m | 64Mi + 64Mi | latency + batch |

The latency-sensitive workload used `nginx:1.25-alpine`. The batch workload
used `alexeiled/stress-ng:latest` with `--cpu 1 --cpu-load 20`.

For Scenario 4, application latency was measured using a fortio load-generator
Job (`fortio/fortio:latest`) running 50 requests per second with 4 concurrent
connections for 60 seconds. The batch stress-ng pods ran concurrently throughout
the load test to create CPU interference.

Each scenario was executed 5 times per scheduler (40 total runs). Results were
aggregated as mean ± standard deviation. Runs that did not complete
successfully were marked as failed and excluded from aggregation without
interpolation.
