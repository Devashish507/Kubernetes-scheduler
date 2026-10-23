# Viva Questions — Likely Examiner Questions

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> 15 likely questions with short, honest answers based on what was actually built.
> Do not claim more than what the data shows.

---

### Q1. Why did you use a weighted linear score instead of a more sophisticated approach (e.g., reinforcement learning)?

**Answer:**  
The weighted linear score has two key properties that make it appropriate for
this project. First, it is *explainable*: every scheduling decision can be
traced to specific R_i, L_i, and P_i values logged at runtime. Second, it is
*deterministic and fast*: the scoring runs in O(nodes) time with a single
Prometheus cache refresh per scheduling cycle, adding at most a few
milliseconds overhead. Reinforcement learning would require a reward function
defined in terms of real energy savings — which are unavailable in a Kind
environment — and a training corpus of diverse scheduling decisions. It would
also make the scheduler a black box, which is problematic for an academic
evaluation where interpretability is valued. The weighted score is a reasonable
starting point that is well-grounded in the literature (similar to the PEAKS
and Trimaran approaches).

---

### Q2. Why was Kepler not used even though it is designed for exactly this purpose?

**Answer:**  
Kepler requires Linux RAPL (Running Average Power Limit) hardware counters
accessible via eBPF. In a Kind cluster, all nodes are Docker containers on
the same host kernel. The containers do not have isolated power domains; RAPL
counters would measure the entire host, not individual containers. Additionally,
eBPF requires elevated privileges that Kind containers do not have by default.
We evaluated Kepler (documented in `docs/metrics.md` and `scripts/install-kepler.sh`)
and confirmed it could not produce meaningful per-node energy data. The decision
to use a simulated linear model was made explicitly to enable reproducibility
on any developer's laptop.

---

### Q3. How is power simulated in this project?

**Answer:**  
Each worker node carries two Kubernetes labels: `energy.project/p-idle`
(power at 0% CPU utilisation) and `energy.project/p-max` (power at 100%
utilisation). The plugin reads these labels and computes:

  P(u) = P_idle + (P_max − P_idle) × u

where u is the current CPU utilisation fraction from Prometheus. The label
values (20–60 W for the efficient node, 40–120 W for medium, 80–200 W for
power-hungry) were chosen to reflect idle-to-peak ratios in SPECpower_ssj2008
submissions. This is a deliberate simplification; real servers show
non-linear power curves, especially at low utilisation.

---

### Q4. What does PEAKS do, and what is original to this project?

**Answer:**  
PEAKS (Power and Energy Aware Kubernetes Scheduler) is an open-source project
by the sustainable-computing-io organisation. It trains a machine-learning
power model on Kepler RAPL metrics and uses it at scheduling time to predict
the energy cost of placing a pod on each node. Our project shares the same
high-level goal but uses an entirely different approach: a hand-crafted linear
model with simulated node labels instead of learned per-node models, and a
composite scoring formula instead of a single energy predictor.
The `pkg/energyaware/` package (energy_aware.go, scoring.go, args.go,
prometheus.go), all manifests, all experiment scripts, and all results are
original to this project. No PEAKS code was used.

---

### Q5. What are the limitations of this experiment?

**Answer:**  
Five main limitations:
1. **Simulated power** — no physical sensors; all figures are linear-model estimates.
2. **Shared host kernel** — all three "nodes" are Docker containers on one machine;
   utilisation interference between containers cannot be isolated.
3. **Small sample size** — 5 runs per cell; insufficient for rigorous statistical
   significance testing.
4. **Single weight configuration** — weights from a 6-point grid search; a finer
   search might find a better trade-off.
5. **Synthetic workloads** — nginx and stress-ng do not represent real production
   applications.

---

### Q6. How were the weights chosen?

**Answer:**  
A grid search evaluated all (wR, wL, wP) triples from {0.2, 0.4, 0.6}³ that
sum to 1.0, giving 6 valid combinations. For each combination, the scheduler
was deployed, Scenario 4 was run once, and we recorded estimated cluster power
and p95 application latency from a fortio load test. The best combination was
selected by the rule: *lowest estimated power among combinations with p95
latency within 10% of the minimum observed p95*. The selected weights were
wR=0.2, wL=0.6, wP=0.2 for latency-sensitive and wR=0.2, wL=0.2, wP=0.6
for batch. Full results are in `results/week6/tuning.csv`.

---

### Q7. What happens when a pod has no `energy.project/workload-type` annotation?

**Answer:**  
The plugin defaults to the batch weight profile (wR=0.2, wL=0.2, wP=0.6).
This is implemented in `workloadWeights()` in `energy_aware.go`: if the
annotation is absent or has any value other than `latency-sensitive`, the
batch profile is returned. The choice of batch as the default reflects the
assumption that unannotated workloads are background tasks where energy
efficiency matters more than low latency.

---

### Q8. What does the utilisation guard do, and why is it set to 80%?

**Answer:**  
If a node's current CPU utilisation is ≥ 80%, the plugin assigns it the
minimum score (MinNodeScore = 0), effectively excluding it from placement
regardless of its power profile or headroom. This is a hard constraint that
prevents the scorer from overloading already-busy nodes simply because their
`R_i` or `L_i` terms are still nominally positive. 80% is a conventional
safety threshold used in Kubernetes resource management; it leaves headroom for
system processes and burst spikes. It is configurable via the `utilizationThreshold`
field in the ConfigMap without rebuilding the image.

---

### Q9. How does the Prometheus integration work, and what happens if Prometheus is unavailable?

**Answer:**  
The plugin uses the official `prometheus/client_golang` library to issue a
single PromQL query that returns per-node CPU utilisation. Results are cached
for 5 seconds to avoid repeated queries during burst scheduling. If the query
fails (timeout, network error, Prometheus down), the plugin falls back to
returning `invalidScore` for all nodes — they receive MinNodeScore after
normalisation. The scheduler then falls back on its other enabled plugins
(if any) or selects based on the remaining valid scores from other nodes.
The 2-second query timeout (`queryCtx`) ensures the scheduler loop is not
stalled indefinitely.

---

### Q10. Why was the default Kubernetes scheduler used as the only baseline?

**Answer:**  
PEAKS was excluded because it requires Kepler metrics unavailable in Kind
(documented in `docs/peaks-setup.md`). Trimaran's TargetLoadPacking plugin
was considered but not deployed within the available time budget (documented in
`docs/trimaran-attempt.md`). The default scheduler is the appropriate primary
baseline because it represents the status quo that any energy-aware scheduler
must improve upon. Adding more baselines without proper deployment validation
would weaken rather than strengthen the comparison.

---

### Q11. Why do some scenarios show the energy-aware scheduler using more power than the default?

**Answer:**  
This is a known and expected result that the project reports honestly.
The most likely explanation (a hypothesis, not a finding) is that concentrating
pods onto the efficient node raises that node's CPU utilisation, which
proportionally raises its estimated power via the linear model. At low
utilisation levels (< 10%), the absolute power difference between nodes is
small (the range is P_idle to P_idle + ~5% of (P_max − P_idle)), so the
scoring signal is weak. The default scheduler's spread placement may, by chance,
result in a lower total estimated power in some runs.

---

### Q12. How reproducible is this experiment?

**Answer:**  
The experiment is reproducible on any machine with Docker Desktop, WSL2,
kind, kubectl, helm, Go ≥ 1.26, and Python 3 with matplotlib and numpy.
A single script (`bash scripts/run-all.sh`) runs the full pipeline.
All tool versions are pinned in `docs/environment.md`. The Helm chart
version is pinned to 91.5.2 in `scripts/install-monitoring.sh`. The only
non-pinned components are `alexeiled/stress-ng:latest` and `fortio/fortio:latest`;
their image digests should be captured for strict reproducibility.

---

### Q13. Is the scheduling overhead acceptable?

**Answer:**  
Yes. All measured scheduling delays were sub-second. The energy-aware scheduler
added overhead from the Prometheus query, but the 5-second cache TTL means
that in a burst of 6 pods, the query fires once and all 6 scheduling decisions
reuse the cached result. The delay figures in `summary.csv` show mean delays
that are comparable to the default scheduler, with the energy-aware scheduler
occasionally showing slightly higher maximum delays on the first scheduling
decision in a run (before the cache is populated).

---

### Q14. What is the significance of the p95 latency measurement?

**Answer:**  
The p95 latency measures the 95th percentile HTTP response time from a fortio
load test targeting the nginx pods in Scenario 4, while batch stress-ng pods
run concurrently. It is the closest proxy this project has to real application
quality-of-service. A higher p95 for the energy-aware scheduler would suggest
that placing latency-sensitive pods on a node shared with batch workloads
increases tail latency. The weight tuning process explicitly protected p95
latency: the selection rule required p95 to remain within 10% of the minimum
before minimising power.

---

### Q15. What would you do differently if you had more time?

**Answer:**  
Four things:
1. **Real hardware** — run on bare-metal or a cloud VM with RAPL access to
   get physical power measurements instead of simulated estimates.
2. **Kepler integration** — recreate the Kind cluster with the required host
   mounts (`/proc`, `/usr/src`) and use Kepler for per-container energy
   estimates.
3. **Bayesian weight optimisation** — replace the 6-point grid search with a
   Gaussian Process-based optimiser to find the Pareto-optimal power/latency
   trade-off more efficiently.
4. **Trimaran comparison** — deploy the TargetLoadPacking plugin as a third
   scheduler baseline for a more complete evaluation.
