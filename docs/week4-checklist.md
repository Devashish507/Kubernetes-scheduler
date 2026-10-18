# Week 4 — Verification Checklist

> **Energy-Aware Kubernetes Scheduler — B.Tech Final-Year Project**

This checklist covers all Week 4 deliverables. Run each verification command in WSL2 Ubuntu from the project root.

---

## Task 1 — R_i (Resource Suitability Term)

**What was done:** Added `scoring.go::computeRi()` which reads `node.Status.Allocatable`, sums already-requested CPU/memory from `nodeInfo.Pods()`, and returns:

$$R_i = \frac{1}{2}\left(\frac{\text{free CPU after pod}}{\text{allocatable CPU}} + \frac{\text{free Mem after pod}}{\text{allocatable Mem}}\right)$$

**Verify:**

```bash
# Run unit tests
cd scheduler/scheduler-plugins
/usr/local/go/bin/go test ./pkg/energyaware/... -v -run TestComputeRi
```

**Expected output:**
```
--- PASS: TestComputeRi_FullHeadroom (0.00s)
--- PASS: TestComputeRi_PartiallyAllocated (0.00s)
--- PASS: TestComputeRi_Overflow (0.00s)
```

---

## Task 2 — L_i (Latency Suitability Term) + Workload Type

**What was done:** `scoring.go::computeLi()` maps utilization → idleness. Pods annotated `energy.project/workload-type=latency-sensitive` use the `LatencySensitiveWeights` profile (wL=0.6 dominant); unannotated or `batch` pods use `BatchWeights` (wP=0.6 dominant).

**Verify:**

```bash
/usr/local/go/bin/go test ./pkg/energyaware/... -v -run TestComputeLi
/usr/local/go/bin/go test ./pkg/energyaware/... -v -run TestPodWorkloadType
```

**Expected output:**
```
--- PASS: TestComputeLi (0.00s)
--- PASS: TestPodWorkloadType_DefaultBatch (0.00s)
--- PASS: TestPodWorkloadType_Latency (0.00s)
```

---

## Task 3 — Configurable Weights

**What was done:** `EnergyAwareArgs` in `args.go` holds two `WeightProfile` structs. They are decoded from the `pluginConfig[].args` JSON in `configmap.yaml` at scheduler startup — no image rebuild needed to change weights.

**Verify weights are loaded from ConfigMap:**

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --tail=20 | grep "EnergyAware plugin initialised"
```

**Expected log line:**
```
EnergyAware plugin initialised  utilizationThreshold=80  
  latencyWeights="wR=0.30 wL=0.60 wP=0.10"  batchWeights="wR=0.30 wL=0.10 wP=0.60"
```

---

## Task 4 — Utilization Guard

**What was done:** In `Score()`, before any term calculation, if `utilization >= args.UtilizationThreshold` (default 80%), the node receives `invalidScore` which normalises to `MinNodeScore=0`. This is a **hard constraint** (feasibility filter), not a soft scoring bias.

**Verify:**

```bash
/usr/local/go/bin/go test ./pkg/energyaware/... -v -run TestScore_UtilizationGuard
```

**Expected output:**
```
--- PASS: TestScore_UtilizationGuard (0.00s)
```

---

## Task 5 — Combined Score() Formula

**What was done:** `energy_aware.go::Score()` now computes all three terms and combines them as:

$$\text{Score}_i = w_R \cdot R_i + w_L \cdot L_i - w_P \cdot P_i$$

Each node emits a structured log at `-v=3`.

**Expected log line (per node per pod):**

```
I1018 ... EnergyAware scored node
  node=energy-worker  workloadType=batch
  weights="wR=0.30 wL=0.10 wP=0.60"
  R_i=0.7234  L_i=0.6500  P_i=0.1000
  deltaPower_W=4.00W  compositeScore=0.209000  rawScore=209000
```

**Run full test suite:**

```bash
cd scheduler/scheduler-plugins
/usr/local/go/bin/go test ./pkg/energyaware/... -v
```

**Expected:** All tests PASS, no FAIL lines.

---

## Task 6 — Rebuild, Redeploy, Verify

```bash
# From project root in WSL2 Ubuntu:
bash scripts/build-scheduler.sh
kubectl apply -f scheduler/manifests/configmap.yaml --context kind-energy
kubectl rollout restart deployment/energy-aware-scheduler -n kube-system --context kind-energy
kubectl rollout status deployment/energy-aware-scheduler -n kube-system --context kind-energy --timeout=120s
```

**Verify the new binary is running:**

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler
# Expected: 1/1 Running, AGE < 5 minutes
```

**Deploy test workloads:**

```bash
kubectl apply -f workloads/nginx-energy-aware.yaml --context kind-energy
kubectl apply -f workloads/batch-energy-aware.yaml --context kind-energy
sleep 30
```

**Check placement and logs:**

```bash
kubectl get pods -o wide --context kind-energy -l energy.project/scheduler=energy-aware-scheduler

# Check scheduler scoring logs
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --tail=60 | grep "EnergyAware scored node"
```

**Expected:** Latency pod lands on `energy-worker` (efficient); batch pod on `energy-worker` or `energy-worker2`, never on `energy-worker3` (power-hungry). Log lines show different `wL`/`wP` values for the two workload types.

**Confirm different weight profiles are used:**

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --tail=60 \
  | grep -E "workloadType=(latency-sensitive|batch)"
```

**Expected:** Two different `workloadType` values visible with correspondingly different weights.

---

## Task 7 — Grafana Dashboard

**Provision dashboard:**

```bash
# Already done by install-monitoring.sh Step 7, or run manually:
{
  cat monitoring/dashboards/dashboard-configmap.yaml
  sed 's/^/    /' monitoring/dashboards/scheduler-comparison.json
} | kubectl apply -n monitoring --context kind-energy -f -
```

**Access Grafana:**

```bash
# Port-forward (or use scripts/port-forward.sh)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
# Open: http://localhost:3000
# Login: admin / (retrieve password with command below)
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

**Verify dashboard exists:**

Navigate to **Dashboards → Energy Scheduler → Energy-Aware Scheduler — Comparison**.

Panels to confirm working:
- ✅ Per-Node CPU Utilization (time series, should show 4 lines)
- ✅ Estimated Node Power (W) — Simulated (time series, 3 worker lines)
- ✅ Total Estimated Cluster Power (stat panel, single number in W)
- ✅ Pods per Node (donut chart)
- ✅ Pod → Node Placement table (shows pod names and their assigned nodes)
- ✅ CPU/Memory Requested / Allocatable (shows resource saturation per node)

---

## Task 8 — All Tests Green

```bash
cd scheduler/scheduler-plugins
/usr/local/go/bin/go test ./pkg/energyaware/... -count=1
```

**Expected:**
```
ok      sigs.k8s.io/scheduler-plugins/pkg/energyaware   0.0XXs
```
