# Week 2 Verification Checklist

**Project:** Energy-Aware Kubernetes Scheduler (B.Tech Final Year Project)

**Week 2 Goal:** A working second scheduler running alongside the default
scheduler, with the `EnergyAware` plugin scoring nodes based on simulated
power-profile labels, and workloads successfully scheduled by it.

Work through each check in order. Every command is exact — copy-paste into
your WSL2 Ubuntu terminal from the project root.

---

## Prerequisites

Before starting Week 2 checks, Week 1 must be complete:

```bash
kubectl get nodes --context kind-energy
# Expected: 4 nodes, all Ready
```

If the cluster is not running, rebuild it:

```bash
bash scripts/setup-cluster.sh
bash scripts/label-nodes.sh
bash scripts/install-monitoring.sh
```

---

## Check 1 — Cluster

```bash
kubectl get nodes --context kind-energy
```

**Expected:**

```
NAME                   STATUS   ROLES           AGE
energy-control-plane   Ready    control-plane   Xm
energy-worker          Ready    <none>          Xm
energy-worker2         Ready    <none>          Xm
energy-worker3         Ready    <none>          Xm
```

All 4 nodes must show `Ready`.

---

## Check 2 — Monitoring Running

```bash
kubectl get pods -n monitoring --context kind-energy
```

**Expected:** All pods in `Running` state (prometheus, grafana, node-exporter,
kube-state-metrics, alertmanager).

---

## Check 3 — Verified PromQL Queries

With port-forwarding running (`bash scripts/port-forward.sh`), open
**http://localhost:9090** and run these verified queries:

### CPU utilisation per node

```promql
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
```

**Expected result:** Values between 0–100 for each node. On an idle cluster,
expect 1–5%.

### Node power-profile labels visible in Prometheus

```promql
kube_node_labels{label_energy_project_power_profile=~".+"}
```

**Expected result:** 3 time series, one for each worker node.
- `label_energy_project_power_profile="efficient"` → energy-worker
- `label_energy_project_power_profile="medium"` → energy-worker2
- `label_energy_project_power_profile="power-hungry"` → energy-worker3

---

## Check 3b — Kepler

Kepler is **NOT installed** on the current cluster.

The existing `cluster/kind-config.yaml` was created without the `/proc` and
`/usr/src` host mounts required by Kepler's eBPF programs.

**Verification:**

```bash
bash scripts/install-kepler.sh
```

**Expected output:** The script detects the missing mounts and prints the
fallback message. It will NOT attempt to install Kepler.

**To enable Kepler**, see `docs/kind-config-kepler.yaml` — this requires
recreating the cluster.

**Fallback:** CPU/memory metrics from node-exporter are used as utilisation
proxies. See `docs/metrics.md` for full detail.

---

## Check 4 — Plugin Unit Tests

```bash
cd scheduler/scheduler-plugins
/usr/local/go/bin/go test ./pkg/energyaware/... -v
```

**Expected output:**

```
=== RUN   TestScore_EfficientNode
--- PASS: TestScore_EfficientNode (0.00s)
=== RUN   TestScore_MediumNode
--- PASS: TestScore_MediumNode (0.00s)
=== RUN   TestScore_PowerHungryNode
--- PASS: TestScore_PowerHungryNode (0.00s)
=== RUN   TestScore_MissingLabel
--- PASS: TestScore_MissingLabel (0.00s)
=== RUN   TestScore_UnrecognisedProfileValue
--- PASS: TestScore_UnrecognisedProfileValue (0.00s)
=== RUN   TestScore_Deterministic
--- PASS: TestScore_Deterministic (0.00s)
=== RUN   TestNormalizeScore_ThreeLabelled
--- PASS: TestNormalizeScore_ThreeLabelled (0.00s)
=== RUN   TestNormalizeScore_MixedLabelledAndUnlabelled
--- PASS: TestNormalizeScore_MixedLabelledAndUnlabelled (0.00s)
=== RUN   TestNormalizeScore_AllUnlabelled
--- PASS: TestNormalizeScore_AllUnlabelled (0.00s)
=== RUN   TestNormalizeScore_AllSameProfile
--- PASS: TestNormalizeScore_AllSameProfile (0.00s)
=== RUN   TestNormalizeScore_EmptyList
--- PASS: TestNormalizeScore_EmptyList (0.00s)
=== RUN   TestNormalizeScore_ScoresInValidRange
--- PASS: TestNormalizeScore_ScoresInValidRange (0.00s)
=== RUN   TestNew
--- PASS: TestNew (0.00s)
=== RUN   TestScoreExtensions
--- PASS: TestScoreExtensions (0.00s)
PASS
ok      sigs.k8s.io/scheduler-plugins/pkg/energyaware   0.027s
```

All 14 tests must pass.

---

## Check 5 — Build the Custom Scheduler

```bash
# From the project root:
bash scripts/build-scheduler.sh
```

Or manually:

```bash
cd scheduler/scheduler-plugins
export PATH=/usr/local/go/bin:$PATH
make build-scheduler

# Verify binary exists:
ls -lh bin/kube-scheduler
# Expected: a binary file, typically 50–100MB

# Verify binary runs:
./bin/kube-scheduler --version
# Expected: Kubernetes v0.0.YYYYMMDD-...
```

---

## Check 6 — Load Image Into KIND

The build script does this automatically. To do it manually:

```bash
# Build the image:
cat > /tmp/energy-scheduler.Dockerfile << 'EOF'
FROM gcr.io/distroless/static:nonroot
WORKDIR /bin
COPY bin/kube-scheduler .
USER 65532:65532
ENTRYPOINT ["/bin/kube-scheduler"]
EOF

cd scheduler/scheduler-plugins
docker build -t energy-aware-scheduler:v0.1.0 \
  -f /tmp/energy-scheduler.Dockerfile .

# Load into KIND:
kind load docker-image energy-aware-scheduler:v0.1.0 --name energy
```

**Verify the image is in KIND nodes:**

```bash
docker exec energy-control-plane crictl images | grep energy-aware-scheduler
# Expected: a line containing energy-aware-scheduler v0.1.0
```

---

## Check 7 — Deploy the Second Scheduler

```bash
# From the project root:
bash scripts/deploy-scheduler.sh
```

Or manually:

```bash
kubectl apply -f scheduler/manifests/serviceaccount.yaml --context kind-energy
kubectl apply -f scheduler/manifests/rbac.yaml --context kind-energy
kubectl apply -f scheduler/manifests/configmap.yaml --context kind-energy
kubectl apply -f scheduler/manifests/deployment.yaml --context kind-energy
```

**Verify the scheduler pod is Running:**

```bash
kubectl get pods -n kube-system --context kind-energy \
  -l app.kubernetes.io/name=energy-aware-scheduler
```

**Expected:**

```
NAME                                   READY   STATUS    RESTARTS   AGE
energy-aware-scheduler-xxxx-yyyy       1/1     Running   0          30s
```

---

## Check 8 — Scheduler Logs Show EnergyAware Scoring

After deploying a workload (Check 9), run:

```bash
kubectl logs -n kube-system --context kind-energy \
  -l app.kubernetes.io/name=energy-aware-scheduler \
  --tail=50 | grep -i "energyaware\|EnergyAware"
```

**Expected log lines** (the format follows klog structured logging):

```
... "EnergyAware scored node" node="energy-worker"  profile="efficient"    rawScore=100
... "EnergyAware scored node" node="energy-worker2" profile="medium"       rawScore=50
... "EnergyAware scored node" node="energy-worker3" profile="power-hungry" rawScore=10
```

These appear at verbosity V(4), which is enabled by `--v=4` in the Deployment.

**If logs don't appear:**

1. Confirm `--v=4` is in the Deployment command args.
2. Confirm the workload uses `schedulerName: energy-aware-scheduler`.
3. Confirm the pod was in `Pending` state before being scheduled (the plugin
   only runs while a pod is pending).

---

## Check 9 — Deploy the Energy-Aware Workload

```bash
kubectl apply -f workloads/nginx-energy-aware.yaml --context kind-energy
```

**Wait for pods to become Running:**

```bash
kubectl get pods -n default --context kind-energy -l app=nginx-energy-aware -w
```

**Press Ctrl+C once all pods show `Running`.**

**Then verify node placement:**

```bash
kubectl get pods -n default --context kind-energy \
  -l app=nginx-energy-aware -o wide
```

**Expected:** Pods are placed on `energy-worker` (the `efficient` node)
because EnergyAware gives it the highest score (100 → normalised to 100
after NormalizeScore).

> **Note:** The default scheduler's filters (NodeResourcesFit, etc.) run first.
> If all resources are available, EnergyAware's preference for `energy-worker`
> should predominate. If the efficient node is full, pods will land on medium.

---

## Check 10 — Verify Scheduler Assignment

```bash
# Get the pod name:
POD=$(kubectl get pods -n default --context kind-energy \
  -l app=nginx-energy-aware \
  -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod "${POD}" -n default --context kind-energy | grep -A 20 'Events:'
```

**Expected Events section:**

```
Events:
  Type    Reason     Age   From                       Message
  ----    ------     ----  ----                       -------
  Normal  Scheduled  Xs    energy-aware-scheduler     Successfully assigned default/nginx-energy-aware-xxxx to energy-worker
  Normal  Pulled     Xs    kubelet                    ...
  Normal  Created    Xs    kubelet                    ...
  Normal  Started    Xs    kubelet                    ...
```

The key line is:
```
From: energy-aware-scheduler    Message: Successfully assigned ...
```

---

## Check 11 — Default Scheduler Still Works

```bash
kubectl apply -f workloads/nginx-default.yaml --context kind-energy
```

**Wait for Running:**

```bash
kubectl get pods -n default --context kind-energy \
  -l app=nginx-default -w
```

**Verify the default scheduler handled it:**

```bash
POD=$(kubectl get pods -n default --context kind-energy \
  -l app=nginx-default \
  -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod "${POD}" -n default --context kind-energy | grep -A5 'Events:'
```

**Expected:**

```
From: default-scheduler     Message: Successfully assigned ...
```

This proves the two schedulers coexist without interfering.

---

## Check 11b — Batch Workload (Optional)

```bash
# Energy-aware scheduler:
kubectl apply -f workloads/batch-energy-aware.yaml --context kind-energy

# Watch until Completed:
kubectl get pods -n default --context kind-energy \
  -l energy.project/workload-type=batch -w
```

**Expected:** Pod completes successfully within ~90 seconds.

---

## Week 2 Summary Table

| Check | Command | Expected |
|---|---|---|
| Cluster ready | `kubectl get nodes` | 4 nodes, all Ready |
| Monitoring running | `kubectl get pods -n monitoring` | All Running |
| CPU metrics | `node_cpu_seconds_total` in Prometheus | Values present |
| Power labels in Prometheus | `kube_node_labels{label_energy_project_power_profile=~".+"}` | 3 series |
| Kepler | `bash scripts/install-kepler.sh` | Documents limitation, does not install |
| Unit tests | `go test ./pkg/energyaware/... -v` | 14 PASS |
| Binary builds | `make build-scheduler` | `bin/kube-scheduler` exists |
| Image in KIND | `crictl images \| grep energy` | Image present |
| Scheduler pod | `kubectl get pods -n kube-system` | 1/1 Running |
| EnergyAware logs | `kubectl logs ... \| grep EnergyAware` | Scored node lines appear |
| Energy-aware pod Running | `kubectl get pods -l app=nginx-energy-aware` | Running |
| Assigned by energy-aware-scheduler | `kubectl describe pod` → Events | `energy-aware-scheduler` in From column |
| Default scheduler still works | `kubectl describe pod` (nginx-default) | `default-scheduler` in From column |

---

## Troubleshooting

### `ImagePullBackOff` on the scheduler pod

```
Error: failed to pull image energy-aware-scheduler:v0.1.0
```

**Cause:** The image was not loaded into KIND, or the name/tag doesn't match.

**Fix:**

```bash
# Reload the image:
kind load docker-image energy-aware-scheduler:v0.1.0 --name energy

# Verify inside the control-plane node:
docker exec energy-control-plane crictl images | grep energy-aware

# Verify the Deployment uses exactly this image name:
kubectl get deployment energy-aware-scheduler -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}' \
  --context kind-energy
# Expected: energy-aware-scheduler:v0.1.0
```

---

### `forbidden` in scheduler logs

```
E ... failed to ... verb="create" resource="bindings" ... reason="Forbidden"
```

**Cause:** Missing RBAC permission.

**Fix:** Do NOT add `cluster-admin`. Instead:

```bash
# 1. Identify the exact verb + resource being denied:
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler \
  --context kind-energy | grep -i "forbidden\|denied"

# 2. Compare with what the current ClusterRole grants:
kubectl describe clusterrole energy-aware-scheduler --context kind-energy

# 3. Add only the specific missing rule to scheduler/manifests/rbac.yaml,
#    then reapply:
kubectl apply -f scheduler/manifests/rbac.yaml --context kind-energy
```

---

### `unknown apiVersion` / scheduler won't start

```
E ... "no kind is registered for the type" apiVersion="kubescheduler.config.k8s.io/v1"
```

**Cause:** The `KubeSchedulerConfiguration` apiVersion doesn't match this
build's Kubernetes version.

**Verify:**

```bash
kubectl version --context kind-energy
# Server: v1.36.x

grep 'k8s.io/kubernetes' scheduler/scheduler-plugins/go.mod
# Should show v1.36.4
```

The correct apiVersion for this build is `kubescheduler.config.k8s.io/v1`
(verified from `scheduler-plugins/apis/config/scheme/scheme_test.go`).

**Do NOT change the apiVersion** — rebuild the image if the Kubernetes version
changes.

---

### `EnergyAware` plugin not found in scheduler logs

```
E ... "plugin not found" name="EnergyAware"
```

**Checklist:**

```bash
# 1. Is energyaware registered in main.go?
grep -n 'energyaware' scheduler/scheduler-plugins/cmd/scheduler/main.go
# Expected: import line + app.WithPlugin(energyaware.Name, energyaware.New)

# 2. Was the image rebuilt AFTER the registration was added?
bash scripts/build-scheduler.sh

# 3. Was the new image loaded into KIND?
kind load docker-image energy-aware-scheduler:v0.1.0 --name energy

# 4. Was the Deployment restarted to pick up the new image?
kubectl rollout restart deployment/energy-aware-scheduler \
  -n kube-system --context kind-energy

# 5. Does the ConfigMap enable EnergyAware in the correct profile?
kubectl get configmap energy-aware-scheduler-config \
  -n kube-system --context kind-energy -o yaml | grep -A5 'score:'
```

---

### EnergyAware scoring logs not appearing

**Cause:** Verbosity is too low, or the workload is not using the custom
scheduler.

**Fix:**

```bash
# Confirm --v=4 is in the Deployment args:
kubectl get deployment energy-aware-scheduler -n kube-system \
  --context kind-energy \
  -o jsonpath='{.spec.template.spec.containers[0].command}'

# Confirm the pod uses the right schedulerName:
kubectl get pod <pod-name> -n default --context kind-energy \
  -o jsonpath='{.spec.schedulerName}'
# Expected: energy-aware-scheduler
```
