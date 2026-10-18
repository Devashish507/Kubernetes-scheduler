# workloads/

This directory will contain Kubernetes workload manifests used for
scheduler comparison experiments (Phase 2 onwards).

**Not used in Week 1.**

## Planned Contents

- CPU-intensive workload deployments
- Memory-intensive workload deployments
- Mixed workloads for scheduler comparison
- Batch job definitions

## Purpose

The same workloads will be submitted against each scheduler
(Default, PEAKS, Custom) under identical conditions, and the following
metrics will be recorded from Prometheus:

- Node placement (which pod lands on which node)
- CPU utilization per node
- Memory utilization per node
- Estimated energy metrics
- Pod scheduling latency
