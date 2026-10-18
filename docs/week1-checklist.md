# Week 1 Verification Checklist

**Project:** Energy-Aware Kubernetes Scheduler (B.Tech Final Year Project)

**Goal:** A working local multi-node Kubernetes cluster with Prometheus +
Grafana installed, and a successfully built `scheduler-plugins` repository.

Work through this checklist top to bottom. Each section tells you what to
run and what a successful result looks like.

---

## 1. Environment

Run each command inside **WSL2 Ubuntu**.

### 1.1 Docker

```bash
docker version
```

**Expected:** Both `Client` and `Server` sections appear with version numbers.
The server is provided by Docker Desktop running on Windows.

If you see `Cannot connect to the Docker daemon`, open Docker Desktop on
Windows and ensure WSL2 integration is enabled for your Ubuntu distribution:
`Settings → Resources → WSL Integration → Ubuntu`.

---

### 1.2 Go

```bash
go version
```

**Expected:**

```
go version go1.26.x linux/amd64
```

The version must be **at least 1.26.0** (required by `scheduler-plugins/go.mod`).

---

### 1.3 kubectl

```bash
kubectl version --client
```

**Expected:** A client version line. The server version is not needed yet.

---

### 1.4 KIND

```bash
kind version
```

**Expected:**

```
kind v0.x.x ...
```

---

### 1.5 Helm

```bash
helm version
```

**Expected:** A version line including `v3.x.x`.

---

### 1.6 Git

```bash
git --version
```

**Expected:** `git version 2.x.x`

---

## 2. Kubernetes Cluster

### 2.1 Verify cluster was created

```bash
kind get clusters
```

**Expected:** `energy` is in the list.

---

### 2.2 Verify all nodes

```bash
kubectl get nodes --context kind-energy
```

**Expected:** 4 nodes appear, all in `Ready` status:

```
NAME                   STATUS   ROLES           AGE
energy-control-plane   Ready    control-plane   Xm
energy-worker          Ready    <none>          Xm
energy-worker2         Ready    <none>          Xm
energy-worker3         Ready    <none>          Xm
```

> If nodes show `NotReady`, wait up to 2 minutes and retry.

---

## 3. Node Labels (Simulated Power Profiles)

> **Reminder:** These labels represent **simulated** power characteristics
> for a local KIND experiment. KIND runs nodes as containers and does NOT
> provide real hardware power measurements.

### 3.1 Verify labels were applied

```bash
kubectl get nodes --context kind-energy \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
```

**Expected output:**

```
NAME                   STATUS   ROLES     POWER-PROFILE    P-IDLE   P-MAX
energy-control-plane   Ready    control   <none>           <none>   <none>
energy-worker          Ready    <none>    efficient        20W      60W
energy-worker2         Ready    <none>    medium           40W      120W
energy-worker3         Ready    <none>    power-hungry     80W      200W
```

### 3.2 Full label view

```bash
kubectl get nodes --show-labels --context kind-energy
```

Look for `energy.project/` prefixed labels on each worker node.

---

## 4. Monitoring Stack

### 4.1 Verify Helm release

```bash
helm list -n monitoring --kube-context kind-energy
```

**Expected:** One release named `kube-prometheus-stack` with status `deployed`.

---

### 4.2 Verify pods are running

```bash
kubectl get pods -n monitoring --context kind-energy
```

**Expected:** All pods in `Running` status. You will see pods for:

- `kube-prometheus-stack-prometheus-*`
- `kube-prometheus-stack-grafana-*`
- `kube-prometheus-stack-alertmanager-*`
- `kube-prometheus-stack-operator-*`
- `kube-prometheus-stack-kube-state-metrics-*`
- `kube-prometheus-stack-prometheus-node-exporter-*` (one per node)

> Pods may take 2-3 minutes to reach `Running` after install.

---

### 4.3 Verify services are present

```bash
kubectl get svc -n monitoring --context kind-energy
```

**Expected:** Services appear for Prometheus, Grafana, and AlertManager.

---

## 5. Grafana

### 5.1 Start port forwarding

```bash
bash scripts/port-forward.sh
```

### 5.2 Open Grafana

Open in your Windows browser: **http://localhost:3000**

### 5.3 Retrieve the Grafana admin password

**Do not hard-code the password.** Retrieve it from the Kubernetes secret
that Helm created automatically:

```bash
kubectl get secret kube-prometheus-stack-grafana \
  -n monitoring \
  --context kind-energy \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

**Username:** `admin`
**Password:** (output of the command above)

> If the secret name does not match, find it with:
> `kubectl get secrets -n monitoring | grep grafana`

### 5.4 Verify login

Log in to Grafana at http://localhost:3000. You should land on the
Grafana home dashboard. Kubernetes dashboards are pre-installed by the
chart.

---

## 6. Prometheus

### 6.1 Access Prometheus (requires port-forward.sh to be running)

Open in your Windows browser: **http://localhost:9090**

### 6.2 Verify targets are being scraped

Navigate to: **http://localhost:9090/targets**

**Expected:** Multiple targets appear in `UP` state (node exporter, kube
state metrics, API server, etc.).

### 6.3 Run a quick query

In the Prometheus UI, enter this query and click **Execute**:

```promql
up
```

**Expected:** Several time series appear, all with value `1`.

---

## 7. Scheduler Plugins Build

### 7.1 Clone the repository (if not already done)

From the project root in WSL2:

```bash
git clone https://github.com/kubernetes-sigs/scheduler-plugins.git \
  scheduler/scheduler-plugins
```

### 7.2 Verify the required Go version

```bash
grep '^go ' scheduler/scheduler-plugins/go.mod
# Expected:  go 1.26.0

go version
# Must be >= go1.26.0
```

### 7.3 Build the binaries

```bash
cd scheduler/scheduler-plugins
go mod download
make build
```

### 7.4 Verify the build succeeded

```bash
ls -lh bin/
# Expected:
#   bin/kube-scheduler
#   bin/controller
```

```bash
./bin/kube-scheduler --version
# Expected: Kubernetes v0.0.YYYYMMDD-...
```

**A successful build is the Week 1 milestone for the scheduler component.**

See [docs/scheduler-build.md](scheduler-build.md) for detailed
troubleshooting.

---

## Week 1 Summary Checklist

| Item | Command | Expected Status |
|---|---|---|
| Docker | `docker version` | Client + Server present |
| Go | `go version` | `>= 1.26.0` |
| kubectl | `kubectl version --client` | Version line present |
| KIND | `kind version` | `v0.x.x` |
| Helm | `helm version` | `v3.x.x` |
| Git | `git --version` | `2.x.x` |
| Cluster exists | `kind get clusters` | `energy` listed |
| 4 nodes ready | `kubectl get nodes` | 1 control-plane + 3 workers, all `Ready` |
| Node labels | `kubectl get nodes -L energy.project/power-profile,...` | Labels on all workers |
| Helm release | `helm list -n monitoring` | `kube-prometheus-stack` `deployed` |
| Pods running | `kubectl get pods -n monitoring` | All `Running` |
| Grafana login | `http://localhost:3000` | Login page loads |
| Prometheus UI | `http://localhost:9090` | UI loads, targets visible |
| Scheduler build | `make build` in `scheduler/scheduler-plugins` | `bin/kube-scheduler` created |
