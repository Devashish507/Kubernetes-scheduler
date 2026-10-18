# Energy-Aware Kubernetes Scheduler

> **B.Tech Final Year Project** — Evaluating energy consumption and
> scheduling efficiency of different Kubernetes schedulers in a local
> multi-node cluster.

---

## Project Overview

This project investigates **energy-aware scheduling in Kubernetes** by
comparing three scheduling strategies under identical workloads:

1. **Kubernetes Default Scheduler** — baseline; schedules based on resource
   availability without energy awareness.
2. **PEAKS Scheduler** — a Power and Energy Aware Kubernetes Scheduler from
   the literature, used as an intermediate comparison point.
3. **Custom Energy-Aware Scheduler Plugin** — a scheduler plugin built using
   the Kubernetes Scheduler Framework that scores nodes based on simulated
   power consumption and resource utilization.

The evaluation measures:

- **Node placement decisions** — which workloads land on which nodes
- **CPU and memory utilization** — collected via Prometheus
- **Estimated energy / power metrics** — via node labels (Week 1) and later
  Kepler (future work)
- **Scheduling latency** — time from pod creation to pod running

> **Honest scope note:** KIND runs Kubernetes nodes as Docker containers on a
> local Windows machine with WSL2. Power values used in Week 1 are
> **simulated labels** — not real hardware measurements. Any tool such as
> Kepler used in later phases should be understood as providing estimates in
> the local container environment, not physical server telemetry.

---

## Planned Scheduler Comparison

```
Kubernetes Default Scheduler
          ↓
    PEAKS Scheduler
          ↓
Custom Energy-Aware Scheduler Plugin
```

---

## Technology Stack

```
Windows 11
   ↓
WSL2 + Ubuntu
   ↓
Docker Desktop (provides Docker daemon, no separate Docker Engine in Ubuntu)
   ↓
KIND (Kubernetes IN Docker) — creates local multi-node cluster
   ↓
Kubernetes cluster (1 control-plane + 3 workers)
   ↓
Helm
   ↓
Prometheus + Grafana (kube-prometheus-stack)
```

---

## Future Architecture (Planned — Not Yet Implemented)

```
                    Kubernetes Cluster
                           │
          ┌────────────────┼────────────────┐
          │                │                │
      Worker 1         Worker 2         Worker 3
      Efficient         Medium         Power Hungry
      (p-idle=20W)   (p-idle=40W)    (p-idle=80W)
      (p-max=60W)    (p-max=120W)    (p-max=200W)
          │                │                │
          └────────────────┼────────────────┘
                           │
                    Monitoring Layer
                           │
                ┌──────────┴──────────┐
                │                     │
           Prometheus              Grafana
                │
          Energy Metrics
                │
        Later: Kepler (estimates in local env)
                │
        Scheduler Evaluation
                │
    ┌───────────┼────────────┐
    │           │            │
 Default      PEAKS       Custom
Scheduler                  Scheduler
                            │
                   Energy-Aware Scoring
                   (estimated power +
                    resource utilization +
                    scheduling latency)
```

The custom scheduler will eventually use the **Kubernetes Scheduler
Framework** (implemented as a plugin via `kubernetes-sigs/scheduler-plugins`)
to score nodes using:

- Estimated idle power (`energy.project/p-idle`)
- Estimated peak power (`energy.project/p-max`)
- Current CPU/memory utilization from Prometheus
- Scheduling latency

> **This scoring algorithm is NOT implemented in Week 1.** Week 1 establishes
> the infrastructure foundation only.

---

## Repository Structure

```text
energy-project/
├── cluster/
│   └── kind-config.yaml        KIND cluster definition (1 cp + 3 workers)
│
├── monitoring/
│   └── values.yaml             Helm values for kube-prometheus-stack
│
├── scheduler/
│   └── scheduler-plugins/      kubernetes-sigs/scheduler-plugins (cloned)
│
├── workloads/                  (future) Kubernetes workload manifests for experiments
│
├── scripts/
│   ├── setup-cluster.sh        Create the KIND cluster
│   ├── teardown.sh             Delete the KIND cluster
│   ├── label-nodes.sh          Apply simulated power-profile labels to workers
│   ├── install-monitoring.sh   Install kube-prometheus-stack via Helm
│   └── port-forward.sh         Forward Grafana + Prometheus to localhost
│
├── docs/
│   ├── scheduler-build.md      How to build scheduler-plugins (verified)
│   └── week1-checklist.md      Step-by-step Week 1 verification checklist
│
└── README.md                   This file
```

---

## Quick Start

All commands must be run **inside WSL2 Ubuntu** from the project root.

### Prerequisites

Verify these are installed before starting:

```bash
docker version       # Docker Desktop WSL2 integration
go version           # must be >= 1.26.0
kubectl version --client
kind version
helm version
git --version
```

### Step 1 — Create the cluster

```bash
bash scripts/setup-cluster.sh
```

**Expected:** 4 nodes (1 control-plane + 3 workers) all in `Ready` status.

**Verify:**

```bash
kubectl get nodes --context kind-energy
```

---

### Step 2 — Label worker nodes

```bash
bash scripts/label-nodes.sh
```

**Expected:** Three workers are labeled with simulated power profiles.

**Verify:**

```bash
kubectl get nodes --context kind-energy \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
```

---

### Step 3 — Install monitoring

```bash
bash scripts/install-monitoring.sh
```

**Expected:** `kube-prometheus-stack` release deployed and all pods Running.

**Verify:**

```bash
kubectl get pods -n monitoring --context kind-energy
kubectl get svc  -n monitoring --context kind-energy
```

---

### Step 4 — Start port forwarding

```bash
bash scripts/port-forward.sh
```

Then open in your Windows browser:

- **Grafana:** http://localhost:3000 (username: `admin`)
- **Prometheus:** http://localhost:9090

Retrieve the Grafana password:

```bash
kubectl get secret kube-prometheus-stack-grafana \
  -n monitoring --context kind-energy \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

---

### Step 5 — Build scheduler-plugins

```bash
git clone https://github.com/kubernetes-sigs/scheduler-plugins.git \
  scheduler/scheduler-plugins

cd scheduler/scheduler-plugins
go mod download
make build

ls bin/
# Expected: bin/kube-scheduler  bin/controller
```

See [docs/scheduler-build.md](docs/scheduler-build.md) for full details
and troubleshooting.

---

### Step 6 — Tear down (when done)

```bash
bash scripts/teardown.sh
```

---

## Important Notes

- **KIND ≠ bare metal.** All power values are simulated labels. Do not
  claim the experiment measures real server energy consumption.
- **Do not modify `go.mod`** in the scheduler-plugins repository to match
  an older Go version. Install the required Go version instead.
- **Helm chart version is pinned** to `91.5.2` (kube-prometheus-stack)
  for reproducibility. If you need to upgrade, update `monitoring/values.yaml`
  and `scripts/install-monitoring.sh` together.
