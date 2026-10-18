# Scoring Model — EnergyAware Scheduler

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**
> Corresponds to **Section 5.6** of the project paper.

---

## Equation

$$\text{Score}_i = w_R \cdot R_i + w_L \cdot L_i - w_P \cdot P_i$$

| Symbol | Name | Range | Definition |
|:---|:---|:---:|:---|
| $R_i$ | Resource suitability | [0, 1] | Fraction of (CPU + memory) headroom remaining **after** placing the pod on node *i*. Higher = more headroom. |
| $L_i$ | Latency suitability | [0, 1] | Idleness of node *i*: $1 - u_i/100$. Fully idle ⇒ $L_i=1$; saturated ⇒ $L_i=0$. |
| $P_i$ | Estimated power term | [0, 1] | Normalised power increase from placing the pod: $\Delta P_i / (P_\text{max} - P_\text{idle})$. Lower power impact ⇒ lower $P_i$ ⇒ better. |
| $w_R$ | Resource weight | $>0$ | Relative importance of headroom. |
| $w_L$ | Latency weight | $>0$ | Relative importance of idleness / latency suitability. |
| $w_P$ | Power weight | $>0$ | Relative importance of estimated power. |

---

## Power Model

Node power is estimated using the **linear SPECpower approximation**:

$$P(u) = P_\text{idle} + (P_\text{max} - P_\text{idle}) \cdot u$$

where $u \in [0, 1]$ is the CPU utilization fraction. Values for $P_\text{idle}$
and $P_\text{max}$ come from the node labels `energy.project/p-idle` and
`energy.project/p-max` applied to each worker during cluster setup.

### Computing $P_i$

1. Read current utilization $u_c$ from Prometheus (cached, 5 s TTL).
2. Estimate utilization after scheduling: $u_a = u_c + \text{pod\_cpu\_request} / \text{node\_allocatable\_cpu}$, capped at 100 %.
3. $\Delta P = P(u_a) - P(u_c)$.
4. Normalise: $P_i = \Delta P / (P_\text{max} - P_\text{idle})$.

---

## Weight Profiles

Two named profiles are selected by the pod annotation
`energy.project/workload-type`:

| Profile | Trigger annotation value | $w_R$ | $w_L$ | $w_P$ | Design rationale |
|:---|:---|:---:|:---:|:---:|:---|
| **latency-sensitive** | `latency-sensitive` | 0.3 | **0.6** | 0.1 | L_i dominant — prefer idle nodes to reduce queuing delay. |
| **batch** (default) | `batch` or absent | 0.3 | 0.1 | **0.6** | P_i dominant — prefer energy-efficient placement. |

Weights are configurable in the `KubeSchedulerConfiguration` ConfigMap
(`scheduler/manifests/configmap.yaml`) without rebuilding the image. After
editing the ConfigMap, restart the scheduler:

```bash
kubectl apply -f scheduler/manifests/configmap.yaml
kubectl rollout restart deployment/energy-aware-scheduler -n kube-system
```

---

## Utilization Guard (Hard Constraint)

Before computing the scoring terms, the plugin checks:

$$u_i \geq \text{utilizationThreshold} \Rightarrow \text{Score}_i = \text{MinNodeScore}$$

Default threshold: **80 %**. This is a *hard constraint* (the feasibility step),
distinct from the soft scoring terms above. Even if a node would win on
$w_R \cdot R_i + w_L \cdot L_i$, it will not be selected if it is already
overloaded. This prevents the scheduler from packing a node beyond safe limits.

---

## NormalizeScore

The raw composite scores across all candidate nodes are linearly mapped to
$[\text{MinNodeScore}+1,\ \text{MaxNodeScore}] = [1, 100]$ so that:

- The **best** feasible node receives score **100**.
- The **worst** feasible node receives score **1**.
- Infeasible nodes (guard triggered, missing labels, Prometheus error) receive **0**.

---

## Example Log Line

When `--v=3` or higher is passed to the scheduler, each scored node emits:

```
I1018 ... EnergyAware scored node
  node=energy-worker workloadType=batch
  weights="wR=0.30 wL=0.10 wP=0.60"
  R_i=0.7234  L_i=0.6500  P_i=0.1000
  deltaPower_W=4.00W  compositeScore=0.209000  rawScore=209000
```

This provides **explainable scoring evidence** for each scheduling decision.
