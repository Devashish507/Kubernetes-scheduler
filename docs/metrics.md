# Energy Metrics Reference

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**
>
> This document records the verified Prometheus metrics and PromQL queries
> used in the Week 2 evaluation.

---

## Important Honesty Note

KIND runs Kubernetes nodes as Docker containers on a local Windows/WSL2
machine. There are no physical power sensors. All energy-related values in
this project are either:

- **Simulated labels** (the `energy.project/p-idle` and `energy.project/p-max`
  labels set during Week 1).
- **Kernel-level estimates** (if Kepler is installed with eBPF support).
- **Proxy metrics** (CPU/memory utilisation from node-exporter).

**Do not describe any metric from this setup as a direct hardware power
measurement.** Always use language such as "estimated", "simulated", or
"proxy metric".

---

## 1. Kepler Status on This Cluster

### Status: Not Installed on the Current Cluster

Kepler (Kubernetes-based Efficient Power Level Exporter) **can** run on
KIND, but it requires the KIND nodes to be created with specific host-path
mounts:

```yaml
# Required extraMounts in kind-config.yaml for Kepler support:
extraMounts:
  - hostPath: /proc
    containerPath: /proc-host
  - hostPath: /usr/src
    containerPath: /usr/src
```

The current `cluster/kind-config.yaml` was created **without** these mounts.
Retroactively adding mounts to a running KIND cluster is not possible without
recreating it.

**To enable Kepler:** see `docs/kind-config-kepler.yaml` and follow the
recreation steps in `scripts/install-kepler.sh`.

### Fallback

All energy-related observation in Week 2 uses:

1. **CPU utilisation** from `kube-prometheus-stack`'s `node-exporter`
   (already running).
2. **Memory utilisation** from node-exporter.
3. **Simulated power labels** on nodes (`energy.project/p-idle`,
   `energy.project/p-max`) as metadata for the scheduler plugin.

---

## 2. CPU Utilisation Metrics

### Metric

```
node_cpu_seconds_total
```

Provided by **kube-prometheus-stack → prometheus-node-exporter**.

This counter tracks cumulative CPU time by mode (`idle`, `user`, `system`,
`iowait`, etc.) and by CPU number. It is present on every node because the
node-exporter DaemonSet runs on all nodes.

### Verified presence

```promql
count by (instance, mode) (node_cpu_seconds_total)
```

This confirms the metric exists and shows which instances are reporting.

### PromQL — CPU usage % per Kubernetes node

```promql
100 - (avg by (node) (
  rate(node_cpu_seconds_total{mode="idle"}[2m])
) * 100)
```

**What it does:** Computes the rate of idle CPU time over the last 2 minutes,
averages across all CPUs on the node, inverts to get the busy percentage.

**Expected result:** A value between 0 and 100 per node label. On an idle
KIND cluster you will typically see values of 1–5%.

**Note:** The `node` label in this context refers to the host-level instance
label from node-exporter, not the Kubernetes node name. To see pod placements
by Kubernetes node name, combine with `kube_pod_info` (see Section 5).

### PromQL — Identify the node-exporter instance for each Kubernetes node

```promql
kube_node_info
```

This joins the Kubernetes node name with the node's IP address, which can be
used to map node-exporter instances back to Kubernetes nodes.

---

## 3. Memory Utilisation Metrics

### Metric

```
node_memory_MemTotal_bytes
node_memory_MemAvailable_bytes
```

Both provided by node-exporter. `MemAvailable` is the Linux kernel's estimate
of how much memory is available for new allocations (more accurate than
`MemFree` for practical purposes).

### PromQL — Memory used % per instance

```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

**Expected result:** Percentage between 0 and 100.

### PromQL — Memory used bytes per instance

```promql
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
```

---

## 4. Node Power-Profile Labels (Simulated)

These are not Prometheus metrics — they are Kubernetes node labels set by
`scripts/label-nodes.sh`. However, kube-state-metrics (part of
kube-prometheus-stack) exposes them as a Prometheus metric:

### Metric

```
kube_node_labels
```

Provided by **kube-prometheus-stack → kube-state-metrics**.

> **Note:** Kubernetes label keys containing `/` and `-` are converted to `_`
> by kube-state-metrics. The label `energy.project/power-profile` becomes
> `label_energy_project_power_profile`.

### PromQL — See power-profile labels on worker nodes

```promql
kube_node_labels{label_energy_project_power_profile=~".+"}
```

**Expected result:** 3 time series, one per worker node, with
`label_energy_project_power_profile` equal to `efficient`, `medium`, or
`power-hungry`.

### PromQL — See all energy-related labels together

```promql
kube_node_labels{
  label_energy_project_power_profile=~".+"
} * on(node) group_left(label_energy_project_p_idle, label_energy_project_p_max)
kube_node_labels
```

---

## 5. Pod Scheduling Observation

### Metric

```
kube_pod_info
```

Provided by **kube-state-metrics**.

This metric links each pod to its scheduled node and includes the
`created_by_kind` and `created_by_name` labels for higher-level tracking.

### PromQL — Which node each pod is running on

```promql
kube_pod_info{namespace="default"}
```

**Expected result:** One series per pod in the `default` namespace, with a
`node` label showing which Kubernetes node the pod was assigned to.

### PromQL — Count of non-system pods per node

```promql
count by (node) (kube_pod_info{namespace!="kube-system", namespace!="monitoring"})
```

### PromQL — Pod phase status

```promql
kube_pod_status_phase{namespace="default"}
```

---

## 6. Scheduling Latency (Proxy Metric)

Kubernetes does not expose scheduling latency as a first-class counter
via kube-state-metrics, but a useful proxy is:

```promql
kube_pod_start_time - kube_pod_created
```

**What it measures:** Wall-clock seconds between when the pod was created
and when it started running. This includes scheduling + image pull + container
start time. It is NOT a pure scheduling latency measurement.

For the project experiment, record this value per pod along with which
scheduler handled it (`kubectl describe pod` → Events section).

---

## 7. Kepler Metrics (Future — If Cluster Is Recreated)

If the cluster is recreated with Kepler support, the following metrics
will be available:

| Metric | Description |
|---|---|
| `kepler_container_joules_total` | Estimated total energy consumed by a container (joules) |
| `kepler_container_core_joules_total` | Estimated CPU core energy (joules) |
| `kepler_container_dram_joules_total` | Estimated DRAM energy (joules) |
| `kepler_node_core_joules_total` | Estimated node CPU energy (joules) |
| `kepler_node_package_joules_total` | Estimated node package energy (joules) |

**Critical disclaimer:** On KIND without RAPL hardware counters, Kepler uses
a power model trained on CPU performance counters to *estimate* energy. The
values will not match real hardware measurements. They are useful for
relative comparisons between scheduling strategies but must be described
as estimates in any academic submission.

### PromQL — Kepler container energy rate (W, estimated)

```promql
rate(kepler_container_joules_total[1m])
```

### PromQL — Kepler energy by node

```promql
sum by (node_name) (rate(kepler_node_package_joules_total[1m]))
```

---

## 8. Summary Table

| Category | Metric | Source | Availability |
|---|---|---|---|
| CPU utilisation | `node_cpu_seconds_total` | node-exporter | ✅ Now |
| Memory utilisation | `node_memory_MemTotal_bytes` | node-exporter | ✅ Now |
| Node power labels | `kube_node_labels` | kube-state-metrics | ✅ Now |
| Pod placement | `kube_pod_info` | kube-state-metrics | ✅ Now |
| Scheduling latency proxy | `kube_pod_start_time - kube_pod_created` | kube-state-metrics | ✅ Now |
| Energy estimate (container) | `kepler_container_joules_total` | Kepler | ⚠️ Needs cluster recreation |
| Energy estimate (node) | `kepler_node_package_joules_total` | Kepler | ⚠️ Needs cluster recreation |
