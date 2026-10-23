# Power Model

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**

This document describes the simulated power model used by the Energy-Aware Scheduler plugin for evaluating energy-aware scheduling strategies on a local KIND cluster.

---

## Formula

The project relies on a linear mathematical approximation to estimate a node's power consumption based on its current CPU utilization:

```
P(u) = P_idle + (P_max - P_idle) × u
```

Where:
* `P(u)` = The estimated power consumption (in Watts).
* `P_idle` = The simulated idle power of the node (in Watts) when it is doing no work (0% utilization).
* `P_max` = The simulated maximum power of the node (in Watts) when under full load (100% utilization).
* `u` = CPU utilization represented as a fraction (e.g., `0.50` for 50%).

---

## Why it is used

This is a deliberately simple linear approximation for the project prototype. Because we are testing scheduling logic (how a scheduler handles scores, computes deltas, and places workloads), we need a predictable and deterministic way to convert CPU utilization into power values. The linear model provides a clear, calculable relationship for the EnergyAware plugin to evaluate candidate nodes.

---

## Important Limitation

> **This is a simulated power model because KIND does not provide independent physical power sensors for each worker node.**

Since the cluster runs as Docker containers sharing the host kernel, we cannot use physical RAPL counters or eBPF mechanisms (like Kepler) to obtain isolated per-node hardware power measurements. As such, the model generates *estimated* power values based on proxy metrics (node-exporter CPU utilization) and static simulated labels (`energy.project/p-idle` and `energy.project/p-max`).

---

## Real-world Justification (SPECpower_ssj2008-style ratios)

While real servers are rarely perfectly linear in their power-to-utilization ratio, using a near-linear approximation is an industry-standard proxy for power modeling. Published **SPECpower_ssj2008** results and industry benchmark curves often display a near-linear utilization-to-power relationship for many modern servers, especially between the 10% and 90% utilization bands.

The project uses this simplified approximation inspired by observed server power/utilization behavior to test the scheduler's decision-making algorithm.

---

## Heterogeneous Node Power Profiles (Week 6)

The three worker nodes carry **clearly different** simulated power profiles to produce meaningful differentiation in the EnergyAware scorer.  Choosing profiles that are too similar would collapse the `P_i` scores and make the energy-aware scheduler behave identically to the default scheduler.

The profiles below are modelled on the idle-to-max ratio patterns observed in SPECpower_ssj2008 submissions:

* Low-power servers (e.g., ARM micro-servers, efficiency-optimised x86): idle typically at **~33–40%** of peak power.
* Mid-range servers: idle at **~33%** of peak.
* High-power workstation-class servers: idle at **~40%** of peak.

To give a meaningful spread while respecting these ratios, the following values were chosen:

| Node | `power-profile` label | `p-idle` (W) | `p-max` (W) | idle/max ratio | Rationale |
|:--|:--|:--:|:--:|:--:|:--|
| `energy-worker` | `efficient` | **20 W** | **60 W** | 33% | Low-power efficiency class (ARM-like). Low idle draws fewer watts; preferred by the energy-aware scorer. |
| `energy-worker2` | `medium` | **40 W** | **120 W** | 33% | Mid-range server class. 2× the idle and max of the efficient node, giving a clear mid-tier score. |
| `energy-worker3` | `power-hungry` | **80 W** | **200 W** | 40% | High-TDP workstation class. Highest absolute watts, penalised most by the `wP` term. |

The idle/max spread across the cluster is **20–200 W**, spanning 10×, which matches the range found in real heterogeneous data-centre mixes and produces clearly distinct `P_i` scores for every combination of utilization values.

> **These are simulated profiles.** No physical hardware is measured.  
> The `p-idle` and `p-max` values are applied as Kubernetes node labels via  
> `scripts/label-nodes.sh` and read at scheduling time by `energy_aware.go`.

### Verification

To confirm the labels are correctly applied to the running cluster:

```bash
kubectl get nodes --context kind-energy \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
```

Expected output (abbreviated):

```
NAME              STATUS   ROLES   …   POWER-PROFILE   P-IDLE   P-MAX
energy-worker     Ready    <none>  …   efficient       20W      60W
energy-worker2    Ready    <none>  …   medium          40W      120W
energy-worker3    Ready    <none>  …   power-hungry    80W      200W
```

### Plugin verification

The Go plugin reads `energy.project/p-idle` and `energy.project/p-max` from
each node's label map in `energy_aware.go` (constants `pIdleLabelKey` and
`pMaxLabelKey`).  If either label is missing or non-numeric the node receives
`invalidScore` and is excluded from placement, which is the correct safe
fallback.  No code change was required; the labels and the plugin agree.
