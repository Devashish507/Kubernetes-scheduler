# Demo Script

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> Target duration: 5–7 minutes. Each step has exact commands and what to say.

---

## Prerequisites

Before the demo starts (do this 5 minutes before):

```bash
# 1. Confirm cluster is running
kubectl get nodes --context kind-energy

# 2. Start port-forwarding (separate terminal, keep it open)
bash scripts/port-forward.sh

# 3. Open Grafana in browser
#    http://localhost:3000
#    Dashboard: "Energy-Aware Scheduler — Comparison"

# 4. Clean up any leftover pods
kubectl delete deployments,pods,jobs --all -n default \
  --context kind-energy --ignore-not-found=true --timeout=60s

# 5. Start the demo script (handles pauses automatically)
bash scripts/demo.sh
```

---

## Step 1 — Cluster Nodes and Power Labels (~45 s)

**Say:**  
"This is a 4-node Kind cluster running on a local machine. One control-plane
and three worker nodes, each with a simulated power profile. These labels
represent different classes of server hardware — an efficient low-power node,
a medium-tier server, and a power-hungry high-TDP machine. The labels are
simulated; there are no real power sensors."

**Command:**
```bash
kubectl get nodes --context kind-energy \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
```

**Expected output:**
```
NAME                    STATUS   ROLES           ... POWER-PROFILE   P-IDLE   P-MAX
energy-control-plane    Ready    control-plane
energy-worker           Ready    <none>          ... efficient       20W      60W
energy-worker2          Ready    <none>          ... medium          40W      120W
energy-worker3          Ready    <none>          ... power-hungry    80W      200W
```

---

## Step 2 — Grafana Dashboard (~45 s)

**Say:**  
"This is the Grafana comparison dashboard. It shows live CPU utilisation
per node, estimated power using the linear model P(u) = P_idle + (P_max − P_idle)·u,
and pod placement. The power values update every 10 seconds."

**Point to:**
- Panel: "Per-Node Estimated Power — Current (W)" — shows colour-coded gauges
- Panel: "Total Estimated Cluster Power (W)"
- Panel: "Pods per Node"

**URL:** http://localhost:3000  
**Dashboard:** Energy-Aware Scheduler — Comparison

---

## Step 3 — Default Scheduler: Deploy Scenario 4 (~60 s)

**Say:**  
"Let's deploy Scenario 4 — a mixed workload of 3 nginx pods and 3 stress-ng
batch pods — using the Kubernetes default scheduler. The default scheduler
has no energy awareness and distributes pods purely by resource availability."

**Commands:**
```bash
kubectl apply -f workloads/scenarios/scenario4-default.yaml --context kind-energy

kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
  -l energy.project/scenario=scenario4 -n default \
  --context kind-energy --timeout=120s

kubectl get pods -n default --context kind-energy -o wide \
  --selector energy.project/scenario=scenario4
```

**Point out:**  
"Look at the NODE column — the default scheduler places pods roughly evenly,
including on energy-worker3, the power-hungry node."

---

## Step 4 — Energy-Aware Scheduler: Deploy Scenario 4 (~75 s)

**Say:**  
"Now let's remove those pods and redeploy with the energy-aware scheduler."

**Commands:**
```bash
kubectl delete -f workloads/scenarios/scenario4-default.yaml \
  --context kind-energy --timeout=60s

kubectl apply -f workloads/scenarios/scenario4-energy-aware.yaml \
  --context kind-energy

kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
  -l energy.project/scenario=scenario4 -n default \
  --context kind-energy --timeout=120s

kubectl get pods -n default --context kind-energy -o wide \
  --selector energy.project/scenario=scenario4
```

**Point out:**  
"Compare the NODE column to the previous run. The energy-aware scheduler
applies the scoring formula Score_i = wR·R_i + wL·L_i − wP·P_i with a
power penalty on energy-worker3."

---

## Step 5 — Scoring Log: R_i, L_i, P_i (~60 s)

**Say:**  
"Every scheduling decision is logged. Let's see how the plugin scored
each candidate node for one of those pods."

**Command:**
```bash
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=energy-aware-scheduler \
  --context kind-energy --tail=60 \
  | grep "EnergyAware scored" | tail -9
```

**Expected log lines (example format):**
```
EnergyAware scored node  node=energy-worker  workloadType=batch
  weights="wR=0.20 wL=0.20 wP=0.60"
  R_i=0.7234  L_i=0.9500  P_i=0.1050
  pAfter_W=26.10W  compositeScore=0.4948  rawScore=494800

EnergyAware scored node  node=energy-worker3  workloadType=batch
  weights="wR=0.20 wL=0.20 wP=0.60"
  R_i=0.6800  L_i=0.9200  P_i=0.4200
  pAfter_W=84.00W  compositeScore=0.1768  rawScore=176800
```

**Say:**  
"energy-worker3 received a high P_i penalty — 0.42 — because it has a
higher absolute power (P_idle=80 W, P_max=200 W). energy-worker scored
much higher and was chosen."

---

## Step 6 — Results Charts (~45 s)

**Say:**  
"Finally, here are the results from 40 experimental runs — 5 per scenario
per scheduler. These charts summarise estimated power and p95 latency."

**Open the files in a file manager or VS Code preview:**
```bash
ls results/week6/charts/
# power_by_scenario.png      — grouped bar chart with error bars
# p95_latency_scenario4.png  — p95 HTTP latency for Scenario 4
# weight_sensitivity.png     — tuning grid: power vs p95 trade-off
```

**Key talking points:**
- Error bars show standard deviation over 5 runs.
- Power differences are small because Kind nodes are containers sharing one
  host — utilisation stays low and nodes' linear power estimates converge.
- p95 latency is from a real HTTP load test (fortio, 50 QPS × 60 s).
- All power numbers are estimated — no real hardware sensors.

---

## Cleanup After Demo

```bash
kubectl delete -f workloads/scenarios/scenario4-energy-aware.yaml \
  --context kind-energy --ignore-not-found=true --timeout=60s
```
