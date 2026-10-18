# Power Model

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**

This document describes the simulated power model used by the Energy-Aware Scheduler plugin for evaluating energy-aware scheduling strategies on a local KIND cluster.

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

## Why it is used

This is a deliberately simple linear approximation for the project prototype. Because we are testing scheduling logic (how a scheduler handles scores, computes deltas, and places workloads), we need a predictable and deterministic way to convert CPU utilization into power values. The linear model provides a clear, calculable relationship for the EnergyAware plugin to evaluate candidate nodes.

## Important Limitation

> **This is a simulated power model because KIND does not provide independent physical power sensors for each worker node.**

Since the cluster runs as Docker containers sharing the host kernel, we cannot use physical RAPL counters or eBPF mechanisms (like Kepler) to obtain isolated per-node hardware power measurements. As such, the model generates *estimated* power values based on proxy metrics (node-exporter CPU utilization) and static simulated labels (`energy.project/p-idle` and `energy.project/p-max`).

## Real-world Justification

While real servers are rarely perfectly linear in their power-to-utilization ratio, using a near-linear approximation is an industry-standard proxy for power modeling. Published **SPECpower_ssj2008** results and industry benchmark curves often display a near-linear utilization-to-power relationship for many modern servers, especially between the 10% and 90% utilization bands. The project uses this simplified approximation inspired by observed server power/utilization behavior to test the scheduler's decision-making algorithm.
