# Week 6 Checklist

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> Run this checklist after each task to confirm success before proceeding.

---

## Task 1 — Application Latency Measurement

### Verification steps

```bash
# 1a. Confirm load-generator.yaml exists
ls workloads/load-generator.yaml

# 1b. Confirm the fortio image is reachable
docker exec energy-worker crictl pull fortio/fortio:latest

# 1c. Apply Scenario 4 first, then apply the load generator
kubectl apply -f workloads/scenarios/scenario4-energy-aware.yaml --context kind-energy
kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
    -l energy.project/scenario=scenario4 -n default --context kind-energy --timeout=120s

kubectl apply -f workloads/load-generator.yaml --context kind-energy
kubectl wait --for=condition=complete job/fortio-load-test \
    -n default --context kind-energy --timeout=150s

kubectl logs -n default -l job-name=fortio-load-test --context kind-energy
```

### Expected output

- `loadtest.txt` (or stdout) contains lines matching:
  ```
  50.00 % <= X.X ms
  75.00 % <= X.X ms
  90.00 % <= X.X ms
  95.00 % <= X.X ms
  99.00 % <= X.X ms
  ```
- No `LOAD_TEST_FAILED` string in the output.
- The stress-ng pods (`scenario4-batch-*`) are still Running while fortio runs.

---

## Task 2 — Heterogeneous Power Profiles

### Verification steps

```bash
# 2a. Confirm node labels
kubectl get nodes --context kind-energy \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max

# 2b. Confirm the plugin reads them (check scheduler logs after a scheduling event)
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler \
  --context kind-energy --tail=50 | grep "EnergyAware scored"
```

### Expected output

```
NAME              STATUS   …   POWER-PROFILE   P-IDLE   P-MAX
energy-worker     Ready    …   efficient       20W      60W
energy-worker2    Ready    …   medium          40W      120W
energy-worker3    Ready    …   power-hungry    80W      200W
```

The scheduler logs must show different `P_i` values for the three nodes,
confirming that the plugin is reading the labels per-node.

---

## Task 3 — Weight Tuning

### Verification steps

```bash
# 3a. Run the grid search
python3 scripts/tune_weights.py

# 3b. Confirm CSV was written
ls -lh results/week6/tuning.csv

# 3c. Count rows (expect 1 header + 6 data rows = 7 lines)
wc -l results/week6/tuning.csv

# 3d. Inspect a sample row
head -2 results/week6/tuning.csv
```

### Expected output of `wc -l`

```
7 results/week6/tuning.csv
```

### Sample row format (tuning.csv)

```
combo_id,lat_wR,lat_wL,lat_wP,bat_wR,bat_wL,bat_wP,total_power_W,p95_latency_ms,util_spread_pct,pods_ready,status
combo01,0.2,0.6,0.2,0.2,0.2,0.6,154.32,18.7,4.12,True,ok
```

- `status` must be `ok` for at least one row.
- `p95_latency_ms` must not be empty for `ok` rows.
- The script prints the selected best combination and the selection rule.

---

## Task 4 — Full Experiment Re-run (5 runs)

### Verification steps

```bash
# 4a. Run the experiments
bash scripts/run-experiments.sh

# 4b. Verify directory structure (4 scenarios × 2 schedulers × 5 runs = 40 dirs)
find results/week6 -mindepth 3 -maxdepth 3 -type d | sort | wc -l
# Expected: 40

# 4c. Check for FAILED markers
find results/week6 -name "FAILED" | sort
# Expected: empty (or list any failed runs)

# 4d. Verify Scenario 4 has loadtest.txt in every run directory
find results/week6/scenario4 -name "loadtest.txt" | sort | wc -l
# Expected: 10 (5 default + 5 energy-aware)
```

### Expected output

- 40 run directories under `results/week6/`.
- Each directory contains: `placement.txt`, `pods.json`, `events.txt`,
  `events.json`, `scoring.txt`, `utilization.json`, `latency.txt`.
- Scenario 4 directories additionally contain `loadtest.txt`.
- FAILED directories are counted, not interpolated.

---

## Task 5 — Analysis and Charts

### Verification steps

```bash
# 5a. Run analysis
python3 scripts/analyze_results.py

# 5b. Confirm summary.csv
ls -lh results/week6/summary.csv
wc -l results/week6/summary.csv   # expected: 9 (1 header + 8 rows)
head -2 results/week6/summary.csv

# 5c. Confirm charts
ls results/week6/charts/
# Expected files:
#   power_by_scenario.png
#   latency_by_scenario.png
#   utilization_scenario4.png
#   p95_latency_scenario4.png
#   weight_sensitivity.png   (generated from tuning.csv)
```

### Expected summary.csv format

```
scenario,scheduler,valid_runs,failed_runs,mean_total_power_W,std_total_power_W,
mean_scheduling_delay_s,std_scheduling_delay_s,mean_p95_latency_ms,std_p95_latency_ms,
mean_util_spread_pct,std_util_spread_pct,...
scenario1,default,5,0,148.xx,x.xx,0.xxx,0.xxx,,,...
```

### Sample row from summary.csv (representative format)

```
scenario4,energy-aware,5,0,155.20,1.34,0.012,0.008,22.4,3.1,2.31,0.45,2.0,2.0,2.0,6.48,6.41,6.45
```

Key checks:
- `valid_runs + failed_runs = 5` for every row.
- `mean_p95_latency_ms` is populated for scenario4 rows; empty for others.
- `std_*` columns are numeric (not blank) when `valid_runs > 1`.

---

## Task 6 — Dashboard Finalization

### Verification steps

```bash
# 6a. Confirm dashboard JSON exists and is valid JSON
python3 -c "import json; json.load(open('monitoring/dashboards/scheduler-comparison.json'))" \
  && echo "Valid JSON"

# 6b. Count panels (expect at least 13 including the 2 new ones)
python3 -c "
import json
d = json.load(open('monitoring/dashboards/scheduler-comparison.json'))
panels = [p for p in d['panels'] if p.get('type') != 'row']
print(f'{len(panels)} non-row panels')
"
# Expected: >= 9 non-row panels

# 6c. Apply dashboard to Grafana (if Grafana is port-forwarded)
# kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 \
#     --context kind-energy &
# curl -s -X POST http://admin:prom-operator@localhost:3000/api/dashboards/import \
#     -H 'Content-Type: application/json' \
#     -d "{\"dashboard\": $(cat monitoring/dashboards/scheduler-comparison.json), \
#          \"overwrite\": true, \"folderId\": 0}"
```

### Expected output

- `"Valid JSON"` is printed.
- At least 9 non-row panels (the 2 new panels added in Week 6 are id=12 and id=13).

---

## Task 7 — Results Narrative

### Verification steps

```bash
ls -lh docs/week6-results-draft.md
grep -c "\[RUN\]" docs/week6-results-draft.md
```

After the experiments complete and results are filled in, the `[RUN]` count
should drop to 0.  All numeric values in the narrative must trace back to a
row in `summary.csv` or `tuning.csv`.

---

## Quick Sanity Check — Run This After Everything

```bash
echo "=== tuning.csv ===" && wc -l results/week6/tuning.csv && head -2 results/week6/tuning.csv
echo ""
echo "=== summary.csv ===" && wc -l results/week6/summary.csv && head -2 results/week6/summary.csv
echo ""
echo "=== charts ===" && ls results/week6/charts/
echo ""
echo "=== FAILED runs ===" && find results/week6 -name "FAILED" | sort
echo ""
echo "=== loadtest files ===" && find results/week6/scenario4 -name "loadtest.txt" | sort
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| `tuning.csv` exists | File present, ≥ 7 lines |
| `summary.csv` exists | File present, exactly 9 lines (1 header + 8 rows) |
| Mean and std columns populated | `std_total_power_W` is numeric for rows with `valid_runs > 1` |
| `mean_p95_latency_ms` non-empty | For scenario4 rows only |
| Charts folder has all 5 PNGs | `power_by_scenario.png`, `latency_by_scenario.png`, `utilization_scenario4.png`, `p95_latency_scenario4.png`, `weight_sensitivity.png` |
| No unplanned interpolation | No FAILED row has a non-empty `mean_*` column |
| Dashboard JSON valid | `python3 -c "import json; json.load(…)"` exits 0 |
