# Trimaran Baseline Evaluation Attempt

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> **Status: Not deployed — see reason below.**

---

## What Trimaran Is

Trimaran is a set of Kubernetes scheduler plugins developed under
[kubernetes-sigs/scheduler-plugins](https://github.com/kubernetes-sigs/scheduler-plugins/tree/master/pkg/trimaran).
The `TargetLoadPacking` plugin schedules pods to achieve a target CPU
utilisation level across nodes (e.g. 40%), consolidating light workloads
and spreading heavy ones to avoid hot spots.

Trimaran is relevant to this project because it also targets resource
efficiency (avoiding both overload and underutilisation) without an
explicit energy model.

---

## Prerequisites Verified Against the Repo

As of the time of evaluation, the Trimaran `TargetLoadPacking` plugin
requires a running **load-watcher** sidecar service
([kubernetes-sigs/load-watcher](https://github.com/kubernetes-sigs/load-watcher))
that exposes real-time node CPU and memory metrics via a REST API.

The load-watcher in turn requires either:
- **Prometheus** already running in the cluster (which we have), or
- **Kubernetes Metrics Server**.

The scheduler plugin must be configured with:
```yaml
pluginConfig:
  - name: TargetLoadPacking
    args:
      defaultRequests:
        cpu: "1000m"
      defaultRequestsMultiplier: "1"
      targetUtilization: 40
      watcherAddress: "http://load-watcher.trimaran-system.svc.cluster.local:2020"
```

Source: README at `kubernetes-sigs/scheduler-plugins/pkg/trimaran/README.md`
(verified; do not guess config keys).

---

## Why It Was Not Deployed

The `TargetLoadPacking` plugin is part of the same `scheduler-plugins`
framework we have already forked. However, adding it would require:

1. **Registering the plugin** in `cmd/scheduler/main.go` alongside
   `EnergyAware` — a code change to the scheduler binary requiring a rebuild
   and reload into KIND.
2. **Deploying the load-watcher** as a separate Deployment in the cluster.
   The load-watcher image at `gcr.io/k8s-staging-scheduler-plugins/load-watcher`
   is a staging image (not a stable release tag), which raised reproducibility
   concerns.
3. **The available time budget (approximately half a day)** was assessed as
   insufficient for steps 1–2 plus running 5 Scenario 4 repetitions reliably.

**Decision:** Trimaran deployment was skipped for Week 7. It is documented as
future work for the paper's Conclusion / Future Work section.

---

## What Would Be Needed to Add Trimaran

1. Add the `TargetLoadPacking` plugin registration in
   `scheduler/scheduler-plugins/cmd/scheduler/main.go`.
2. Deploy the load-watcher using the latest tag from
   `gcr.io/k8s-staging-scheduler-plugins/load-watcher` (pin to a digest).
3. Add a `KubeSchedulerConfiguration` profile `trimaran-scheduler` with
   the `TargetLoadPacking` pluginConfig.
4. Create scenario manifests `scenario4-trimaran.yaml`.
5. Run Scenario 4 five times and add results to `summary.csv`.

This is feasible as a one-day follow-up task if the cluster is still available.
