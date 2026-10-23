# Paper Edits Required

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> This document lists sentences in the existing paper draft that need to change
> from future/proposed tense to past tense, now that the implementation and
> experiments are complete.  
> Format: **Original → Suggested replacement**

---

## Abstract

**Original (typical future-tense abstract language):**
> "This paper proposes an energy-aware Kubernetes scheduler plugin that scores
> nodes using a composite function of resource availability, latency suitability,
> and estimated power consumption."

**Suggested replacement (past tense):**
> "This paper presents an energy-aware Kubernetes scheduler plugin that scored
> nodes using a composite function of resource availability, latency suitability,
> and estimated power consumption, and evaluated it against the Kubernetes
> default scheduler across four synthetic workload scenarios."

---

**Original:**
> "We will evaluate the plugin against the default Kubernetes scheduler and the
> PEAKS energy-aware scheduler."

**Suggested replacement:**
> "The plugin was evaluated against the default Kubernetes scheduler. PEAKS was
> excluded because it requires Kepler RAPL metrics unavailable in the Kind
> container environment."

---

## Section 3.3 — Plugin Design (or equivalent)

**Original:**
> "The scoring formula will be:  Score_i = wR*R_i + wL*L_i - wP*P_i"

**Suggested replacement:**
> "The scoring formula was:  Score_i = wR*R_i + wL*L_i - wP*P_i"

---

**Original:**
> "Nodes exceeding the configurable utilisation threshold will receive the
> minimum score and be excluded from placement."

**Suggested replacement:**
> "Nodes at or above the 80% utilisation threshold received the minimum score
> (MinNodeScore = 0) and were excluded from placement."

---

**Original (weight profile description in future tense):**
> "Two weight profiles will be defined: latency-sensitive (wL dominant) and
> batch (wP dominant). Weights will be configurable via the ConfigMap."

**Suggested replacement:**
> "Two weight profiles were defined: latency-sensitive (wR=0.2, wL=0.6, wP=0.2)
> and batch (wR=0.2, wL=0.2, wP=0.6). Weights were configurable via the
> KubeSchedulerConfiguration ConfigMap without rebuilding the image.
> The reported weights are the output of a grid search over {0.2, 0.4, 0.6}³."

---

## Section 5.9 — Experimental Scenarios

**Original:**
> "Four scenarios will be evaluated…"

**Suggested replacement:**
> "Four scenarios were evaluated…"

---

## Section 6 — Expected Impact / Evaluation of Claims

The following table assesses each claim in Section 6 against the experimental data.
Fill the "Supported?" column from `results/week7/deltas.csv` after experiments complete.

| Claim (original text) | Supported by data? | Notes |
|:---|:---:|:---|
| "The energy-aware scheduler will reduce cluster power consumption." | `[CSV]` | Supported if Δ% for total_power < 0 in majority of scenarios AND larger_than_std=True. |
| "The energy-aware scheduler will prefer nodes with lower power profiles." | `[CSV]` | Check placements_energy_worker3_pwr column — lower = preferred efficient nodes. |
| "The scheduling overhead will remain sub-second." | Supported | All measured delays were < 1 s across all 40 runs. |
| "Application latency will not be significantly degraded." | `[CSV]` | Check delta_pct for p95_latency_ms in scenario4; assess against 10% threshold. |
| "PEAKS will serve as a valid comparison baseline." | Not supported | PEAKS excluded due to Kepler dependency on Kind. Documented in peaks-setup.md. |

---

## Section 3.x — Prometheus Cache

**Original (if written in future tense):**
> "A cache with a 5-second TTL will be used to avoid overloading Prometheus."

**Suggested replacement:**
> "A cache with a 5-second TTL was used to avoid overloading Prometheus during
> burst pod scheduling. The cache was implemented in `prometheus.go`."

---

## General Rule for Remaining Tense Fixes

Search the paper for any of these patterns and convert to past tense:

| Pattern | Replace with |
|:---|:---|
| "will be evaluated" | "was evaluated" |
| "will deploy" / "will implement" | "was deployed" / "was implemented" |
| "will compare" | "compared" |
| "is proposed" | "was designed" |
| "is expected to" | "was expected to" / (delete if claim is now confirmed) |
| "future work" in Section 6 if now done | Move to Results or Implementation |
