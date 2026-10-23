# Demo Fallback Plan

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> Use this document if the cluster fails to start or behaves unexpectedly
> on the day of the demo or viva.

---

## Fallback Assets Location

```
results/week7/demo-backup/
├── node-labels.txt        kubectl get nodes output showing power labels
├── pods-default.txt       kubectl get pods -o wide for Scenario 4 (default)
├── pods-energy-aware.txt  kubectl get pods -o wide for Scenario 4 (energy-aware)
├── scoring-log.txt        scheduler log lines showing R_i, L_i, P_i
└── charts/                copies of the final PNG charts
    ├── power_by_scenario.png
    ├── latency_by_scenario.png
    ├── utilization_scenario4.png
    ├── p95_latency_scenario4.png
    └── weight_sensitivity.png
```

---

## How to Populate the Backup Folder

Run these commands **once, during a successful demo dry-run**, to capture
real output. Store the output files in `results/week7/demo-backup/`.

```bash
BACKUP="results/week7/demo-backup"
mkdir -p "${BACKUP}/charts"
CONTEXT="kind-energy"

# 1. Node labels
kubectl get nodes --context "${CONTEXT}" \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max \
  > "${BACKUP}/node-labels.txt"

# 2. Default-scheduler pod placement (run after Scenario 4 default is deployed)
kubectl get pods -n default --context "${CONTEXT}" -o wide \
  --selector energy.project/scenario=scenario4 \
  > "${BACKUP}/pods-default.txt"

# 3. Energy-aware pod placement (run after Scenario 4 energy-aware is deployed)
kubectl get pods -n default --context "${CONTEXT}" -o wide \
  --selector energy.project/scenario=scenario4 \
  > "${BACKUP}/pods-energy-aware.txt"

# 4. Scheduler scoring logs
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=energy-aware-scheduler \
  --context "${CONTEXT}" --tail=60 \
  | grep "EnergyAware scored" \
  > "${BACKUP}/scoring-log.txt"

# 5. Copy charts
cp results/week6/charts/*.png "${BACKUP}/charts/"

echo "Backup assets saved to ${BACKUP}/"
ls -lh "${BACKUP}/"
```

---

## What to Show If the Cluster Is Down

1. **Node labels:**  
   Open `results/week7/demo-backup/node-labels.txt` in a terminal (`cat`).  
   Explain: "This is the output from the running cluster — three worker nodes
   with simulated power profiles of 20–60 W, 40–120 W, and 80–200 W."

2. **Pod placement:**  
   `cat results/week7/demo-backup/pods-default.txt`  
   `cat results/week7/demo-backup/pods-energy-aware.txt`  
   Compare the NODE column between the two files.

3. **Scoring logs:**  
   `cat results/week7/demo-backup/scoring-log.txt`  
   Walk through the R_i, L_i, P_i values and explain the formula.

4. **Charts:**  
   Open the PNG files in `results/week7/demo-backup/charts/` using any
   image viewer. The charts are self-contained with titles and labels.

5. **Grafana:**  
   If Grafana is unavailable, describe what each dashboard panel would show:
   - "Per-Node CPU Utilisation" — timeseries of the three worker nodes.
   - "Estimated Node Power" — colour-coded gauge (green=efficient, red=hungry).
   - "Pods per Node" — donut chart showing placement distribution.

---

## Common Cluster Failures and Quick Fixes

| Symptom | Likely cause | Quick fix |
|:---|:---|:---|
| `kubectl get nodes` hangs | Docker Desktop not running | Start Docker Desktop, wait 60 s |
| Scheduler pod CrashLoopBackOff | ConfigMap syntax error | `kubectl describe pod <scheduler-pod> -n kube-system` for details |
| Prometheus port-forward fails | Port 9098 already in use | `lsof -i :9098` and kill the process |
| Grafana shows no data | Prometheus scrape not ready | Wait 30 s; check `kubectl get pods -n monitoring` |
| fortio Job fails | nginx Service not ready | Verify `kubectl get svc scenario4-nginx-svc -n default` exists |
