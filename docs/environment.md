# Environment — Pinned Versions

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> Record the exact tool versions used when the reported results were produced.
> Update this file if you reproduce the experiment on a different machine.

---

## 1. Host Environment

| Component | Value |
|:---|:---|
| Host OS | Windows 11 (22H2+) |
| Virtualisation | WSL2 (Ubuntu 22.04 LTS) |
| Docker | Docker Desktop (WSL2 integration enabled) |

---

## 2. Kubernetes Tooling

Run these commands to capture the versions actually used and paste the output below:

```bash
# Capture and record:
kubectl version --context kind-energy
kind version
helm version --short
```

**kubectl version output:**
```
# PASTE OUTPUT OF: kubectl version --context kind-energy
```

**kind version output:**
```
# PASTE OUTPUT OF: kind version
```

**helm version output:**
```
# PASTE OUTPUT OF: helm version --short
```

---

## 3. Container Images (Pinned)

| Component | Image | Tag / Version |
|:---|:---|:---|
| KIND node image | `kindest/node` | `v1.31.0` (from `cluster/kind-config.yaml`) |
| Energy-aware scheduler | `energy-aware-scheduler` | `v0.1.0` (built locally) |
| Base image (scheduler) | `gcr.io/distroless/static` | `nonroot` |
| nginx (latency workload) | `nginx` | `1.25-alpine` |
| stress-ng (batch workload) | `alexeiled/stress-ng` | `latest` |
| fortio (load generator) | `fortio/fortio` | `latest` |

> **Note:** `latest` tags for stress-ng and fortio are used as convenience
> images for simulation only. For strict reproducibility, pin to a specific
> digest by running `docker inspect <image>` and recording the `RepoDigests` field.

---

## 4. Helm Charts (Pinned)

| Chart | Repository | Version |
|:---|:---|:---|
| `kube-prometheus-stack` | `prometheus-community` | `91.5.2` |

Verify the pinned version in `scripts/install-monitoring.sh` (`CHART_VERSION`
variable) and `monitoring/values.yaml` (comment header).

---

## 5. Go (Scheduler Plugin)

| Component | Version |
|:---|:---|
| Go compiler | `>= 1.26.0` (required by `scheduler/scheduler-plugins/go.mod`) |
| Module path | `sigs.k8s.io/scheduler-plugins` |

```bash
# Capture:
go version
```

**go version output:**
```
# PASTE OUTPUT OF: go version
```

---

## 6. Python (Analysis Scripts)

```bash
# Capture:
python3 --version
```

**python3 version output:**
```
# PASTE OUTPUT OF: python3 --version
```

### Python package requirements

The `scripts/requirements.txt` file lists all packages used by the analysis
and tuning scripts.  Install with:

```bash
pip install -r scripts/requirements.txt
```

Contents of `scripts/requirements.txt`:

```
matplotlib>=3.7
numpy>=1.24
```

> No additional packages are required. `csv`, `json`, `subprocess`, `re`,
> `pathlib`, `urllib` are part of the Python standard library.

---

## 7. Scheduler Plugin Dependencies

From `scheduler/scheduler-plugins/go.mod` (key dependencies):

| Dependency | Version |
|:---|:---|
| `k8s.io/kube-scheduler/framework` | (pinned in go.mod — check file for exact version) |
| `github.com/prometheus/client_golang` | (pinned in go.mod) |
| `github.com/prometheus/common` | (pinned in go.mod) |
| `k8s.io/klog/v2` | (pinned in go.mod) |

To see all pinned versions:

```bash
cat scheduler/scheduler-plugins/go.mod
cat scheduler/scheduler-plugins/go.sum | head -30
```
