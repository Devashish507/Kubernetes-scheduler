#!/usr/bin/env bash
# =============================================================================
# scripts/run-experiments.sh
# Week 5 Automated Experiment Runner
# Runs Scenarios 1-4 for default-scheduler and energy-aware-scheduler (3 runs each).
# Total: 4 scenarios x 2 schedulers x 3 runs = 24 runs.
# =============================================================================
set -euo pipefail

CONTEXT="kind-energy"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${BASE_DIR}/results/week5"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Schedulers to test (PEAKS excluded per docs/peaks-setup.md)
SCHEDULERS=("default" "energy-aware")
SCENARIOS=("scenario1" "scenario2" "scenario3" "scenario4")
RUNS=(1 2 3)

cleanup_namespace() {
  log "Cleaning up default namespace..."
  kubectl delete deployments,pods,jobs --all -n default --context "${CONTEXT}" --ignore-not-found=true --timeout=60s 2>/dev/null || true
  # Wait until all pods are gone
  local count=1
  while [ "${count}" -gt 0 ]; do
    count=$(kubectl get pods -n default --context "${CONTEXT}" --no-headers 2>/dev/null | wc -l || echo 0)
    if [ "${count}" -gt 0 ]; then
      sleep 2
    fi
  done
  sleep 3
}

query_prometheus() {
  local out_file=$1
  local pf_port=9098

  # Start port-forward in background
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus "${pf_port}:9090" --context "${CONTEXT}" >/dev/null 2>&1 &
  local pf_pid=$!
  sleep 3

  # Query node utilization mapped by nodename
  local promql='100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) * on(instance) group_left(nodename) node_uname_info'
  curl -s -G "http://localhost:${pf_port}/api/v1/query" \
    --data-urlencode "query=${promql}" > "${out_file}" 2>/dev/null || echo '{"data":{"result":[]}}' > "${out_file}"

  kill "${pf_pid}" 2>/dev/null || true
}

compute_latency() {
  local pods_json=$1
  local events_json=$2
  local out_file=$3

  python3 - <<EOF > "${out_file}"
import json, sys
from datetime import datetime

try:
    with open("${pods_json}") as f:
        pods = json.load(f).get("items", [])
except Exception as e:
    pods = []

try:
    with open("${events_json}") as f:
        events = json.load(f).get("items", [])
except Exception as e:
    events = []

# Map scheduled events by pod name
scheduled_times = {}
for ev in events:
    obj = ev.get("involvedObject", {})
    if obj.get("kind") == "Pod" and ev.get("reason") == "Scheduled":
        pod_name = obj.get("name")
        ts = ev.get("eventTime") or ev.get("firstTimestamp") or ev.get("metadata", {}).get("creationTimestamp")
        if pod_name and ts:
            scheduled_times[pod_name] = ts

print(f"{'Pod':<45} {'Created':<25} {'Scheduled':<25} {'Delay(s)':<10}")
print("-" * 110)

delays = []
for p in pods:
    pname = p.get("metadata", {}).get("name", "unknown")
    created_str = p.get("metadata", {}).get("creationTimestamp", "")
    
    # Try condition first
    sched_str = None
    for cond in p.get("status", {}).get("conditions", []):
        if cond.get("type") == "PodScheduled" and cond.get("status") == "True":
            sched_str = cond.get("lastTransitionTime")
            break
            
    if not sched_str and pname in scheduled_times:
        sched_str = scheduled_times[pname]
        
    delay = 0.0
    if created_str and sched_str:
        try:
            t0 = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
            t1 = datetime.fromisoformat(sched_str.replace("Z", "+00:00"))
            delay = max(0.0, (t1 - t0).total_seconds())
            delays.append(delay)
        except Exception:
            pass
            
    print(f"{pname:<45} {str(created_str):<25} {str(sched_str):<25} {delay:<10.3f}")

if delays:
    print("-" * 110)
    print(f"Mean Delay: {sum(delays)/len(delays):.3f}s | Min: {min(delays):.3f}s | Max: {max(delays):.3f}s")
EOF
}

run_single_experiment() {
  local scenario=$1
  local sched=$2
  local run_num=$3

  local manifest="${BASE_DIR}/workloads/scenarios/${scenario}-${sched}.yaml"
  local run_dir="${RESULTS_DIR}/${scenario}/${sched}/run${run_num}"

  mkdir -p "${run_dir}"
  log "======================================================================"
  log "STARTING: Scenario=${scenario} | Scheduler=${sched} | Run=${run_num}"
  log "Manifest: ${manifest}"
  log "======================================================================"

  cleanup_namespace

  local start_time
  start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Apply workload
  kubectl apply -f "${manifest}" --context "${CONTEXT}"

  # Wait for pods to reach Running
  log "Waiting for pods to be Running (timeout: 120s)..."
  if ! kubectl wait --for=jsonpath='{.status.phase}'=Running pod -l "energy.project/scenario=${scenario}" -n default --context "${CONTEXT}" --timeout=120s; then
    log "WARNING: Wait timeout reached or partial readiness."
  fi

  # Allow metrics scrape to register (Prometheus scrape interval is typically 10-15s)
  log "Waiting 15s for steady-state metric stabilization..."
  sleep 15

  # Capture placement
  log "Capturing placement..."
  kubectl get pods -n default --context "${CONTEXT}" -o wide > "${run_dir}/placement.txt"
  kubectl get pods -n default --context "${CONTEXT}" -o json > "${run_dir}/pods.json"

  # Capture events
  log "Capturing events..."
  kubectl get events -n default --context "${CONTEXT}" --sort-by=.metadata.creationTimestamp > "${run_dir}/events.txt"
  kubectl get events -n default --context "${CONTEXT}" -o json > "${run_dir}/events.json"

  # Capture scheduler logs for this run
  log "Capturing scheduler logs..."
  kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --context "${CONTEXT}" --since-time="${start_time}" > "${run_dir}/scoring.txt" 2>&1 || true

  # Capture Prometheus utilization
  log "Capturing Prometheus node utilization..."
  query_prometheus "${run_dir}/utilization.json"

  # Compute latency
  log "Computing scheduling latency..."
  compute_latency "${run_dir}/pods.json" "${run_dir}/events.json" "${run_dir}/latency.txt"

  log "Completed Run ${run_num} for ${scenario} (${sched})."

  # Clean up manifest
  kubectl delete -f "${manifest}" --context "${CONTEXT}" --timeout=60s 2>/dev/null || true
  cleanup_namespace
  sleep 5
}

# ── Main Loop ───────────────────────────────────────────────────────────────
log "Initializing Week 5 experiment campaign..."
mkdir -p "${RESULTS_DIR}"

for scen in "${SCENARIOS[@]}"; do
  for sched in "${SCHEDULERS[@]}"; do
    for run in "${RUNS[@]}"; do
      run_single_experiment "${scen}" "${sched}" "${run}"
    done
  done
done

log "All 24 experimental runs completed successfully!"
log "Results saved under ${RESULTS_DIR}/"
