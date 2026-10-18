# PEAKS Scheduler Baseline Evaluation

## 1. Repository Details
- **Repository used**: `sustainable-computing-io/peaks`
- **Installation dependencies**: Helm, kubectl, Prometheus, and Kepler.

## 2. Kepler Dependency & Evaluation
After analyzing the PEAKS source code, it was determined that PEAKS **hard-depends on Kepler metrics** for both training its power models and making runtime scheduling decisions. It specifically requires metrics such as:
- `kepler_node_package_joules_total`
- `kepler_node_dram_joules_total`

### Limitation on KIND
Because this project is being run on a local Docker-based KIND cluster (where Kubernetes nodes are simulated as Docker containers sharing the host kernel), Kepler cannot reliably access the underlying RAPL/eBPF hardware counters. The required energy metrics are unavailable.

Consequently, **PEAKS cannot be fully deployed or evaluated locally in this KIND environment**. We have documented this gap, and as such, the results and analysis will focus primarily on comparing the Kubernetes Default Scheduler against our custom `energy-aware-scheduler` which uses a simulated power model.
