#!/usr/bin/env bash
# =============================================================================
# scripts/run-experiments.sh
# Week 6 Automated Experiment Runner (updated from Week 5)
#
# Changes from Week 5:
#   - RUNS expanded from 3 to 5 per scenario/scheduler combination.
#   - RESULTS_DIR now points to results/week6/.
#   - Scenario 4 additionally runs the fortio load-generator Job after pods are
#     Running and saves its output to <run_dir>/loadtest.txt.
#   - Batch (stress-ng) pods run concurrently with the load test; the load test
#     waits for ALL pods (latency + batch) before starting.
#   - Failed or missing runs are left with a "FAILED" marker file; no values
#     are interpolated.
#
# Total: 4 scenarios × 2 schedulers × 5 runs = 40 runs.
# PEAKS excluded per docs/peaks-setup.md (hard dependency on Kepler).
# =============================================================================
set -euo pipefail

CONTEXT="kind-energy"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${BASE_DIR}/results/week6"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Schedulers to test (PEAKS excluded per docs/peaks-setup.md)
SCHEDULERS=("default" "energy-aware")
SCENARIOS=("scenario1" "scenario2" "scenario3" "scenario4")
RUNS=(1 2 3 4 5)

# ---------------------------------------------------------------------------
# cleanup_namespace — delete all workload pods and wait until they are gone.
# ---------------------------------------------------------------------------
cleanup_namespace() {
  log "Cleaning up default namespace..."
  kubectl delete deployments,pods,jobs \
    --all -n default \
    --context "${CONTEXT}" \
    --ignore-not-found=true \
    --timeout=90s 2>/dev/null || true

  local count=1
  while [ "${count}" -gt 0 ]; do
    count=$(kubectl get pods -n default --context "${CONTEXT}" \
              --no-headers 2>/dev/null | wc -l || echo 0)
    if [ "${count}" -gt 0 ]; then
      sleep 2
    fi
  done
  sleep 3
}

# ---------------------------------------------------------------------------
# query_prometheus — snapshot current node CPU utilisation via Prometheus.
# ---------------------------------------------------------------------------
query_prometheus() {
  local out_file=$1
  local pf_port=9098

  kubectl port-forward -n monitoring \
    svc/kube-prometheus-stack-prometheus "${pf_port}:9090" \
    --context "${CONTEXT}" >/dev/null 2>&1 &
  local pf_pid=$!
  sleep 3

  # PromQL: per-node CPU utilisation %.
  # node_uname_info join gives the friendly nodename label.
  local promql='100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) * on(instance) group_left(nodename) node_uname_info'
  curl -s -G "http://localhost:${pf_port}/api/v1/query" \
    --data-urlencode "query=${promql}" \
    > "${out_file}" 2>/dev/null \
    || echo '{"data":{"result":[]}}' > "${out_file}"

  kill "${pf_pid}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# compute_latency — parse scheduling delay from pods.json + events.json.
# ---------------------------------------------------------------------------
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
except Exception:
    pods = []

try:
    with open("${events_json}") as f:
        events = json.load(f).get("items", [])
except Exception:
    events = []

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

# ---------------------------------------------------------------------------
# run_load_test — launch the fortio Job against the Scenario 4 nginx Service.
#
# Prerequisites (applied before this function is called):
#   - scenario4-nginx-svc Service must exist (comes from load-generator.yaml).
#   - The nginx Deployment pods must already be Running.
#   - stress-ng (batch) pods must also be Running concurrently.
#
# The function waits for the Job to complete (success or failure) and then
# copies the fortio log to <run_dir>/loadtest.txt.  If the Job fails, the
# output is still saved and the function returns a non-zero exit code so the
# caller can write a FAILED marker (but does not abort the whole campaign).
# ---------------------------------------------------------------------------
run_load_test() {
  local run_dir=$1

  log "  [Scenario 4] Applying load-generator Service + Job..."

  # Apply Service and Job from load-generator.yaml.
  kubectl apply -f "${BASE_DIR}/workloads/load-generator.yaml" --context "${CONTEXT}"

  log "  [Scenario 4] Waiting for fortio Job to complete (timeout: 150s)..."
  if kubectl wait --for=condition=complete job/fortio-load-test \
       -n default --context "${CONTEXT}" --timeout=150s 2>/dev/null; then
    log "  [Scenario 4] Load test completed."
  else
    log "  [Scenario 4] WARNING: fortio Job did not complete successfully."
    echo "LOAD_TEST_FAILED" > "${run_dir}/loadtest.txt"
    # Delete the Job so subsequent runs start clean.
    kubectl delete job fortio-load-test -n default \
      --context "${CONTEXT}" --ignore-not-found=true 2>/dev/null || true
    return 1
  fi

  # Save the fortio text output (includes p50/p75/p90/p99/p99.9 lines).
  kubectl logs -n default -l job-name=fortio-load-test \
    --context "${CONTEXT}" > "${run_dir}/loadtest.txt" 2>/dev/null || \
    echo "LOG_CAPTURE_FAILED" > "${run_dir}/loadtest.txt"

  log "  [Scenario 4] Load test output saved to ${run_dir}/loadtest.txt"

  # Clean up Job (Service persists; next run will re-apply idempotently).
  kubectl delete job fortio-load-test -n default \
    --context "${CONTEXT}" --ignore-not-found=true 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# run_single_experiment — execute one scenario/scheduler/run combination.
# ---------------------------------------------------------------------------
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

  # Apply workload manifest.
  kubectl apply -f "${manifest}" --context "${CONTEXT}"

  # Wait for ALL pods in the scenario to reach Running.
  # For Scenario 4 this includes both latency-sensitive (nginx) and batch
  # (stress-ng) pods.  The load test must not start until both are Running.
  log "Waiting for pods to be Running (timeout: 120s)..."
  if ! kubectl wait \
      --for=jsonpath='{.status.phase}'=Running \
      pod \
      -l "energy.project/scenario=${scenario}" \
      -n default \
      --context "${CONTEXT}" \
      --timeout=120s; then
    log "WARNING: Wait timeout reached or partial readiness – marking run as FAILED."
    echo "PODS_NOT_READY" > "${run_dir}/FAILED"
    cleanup_namespace
    return 0
  fi

  # Allow metrics scrape to register.
  log "Waiting 15s for steady-state metric stabilisation..."
  sleep 15

  # ── For Scenario 4: run load test while batch pods are still up ────────────
  if [ "${scenario}" = "scenario4" ]; then
    local load_ok=true
    run_load_test "${run_dir}" || load_ok=false
    if [ "${load_ok}" = "false" ]; then
      log "  Load test failed; recording FAILED marker but continuing data capture."
      echo "LOAD_TEST_FAILED" > "${run_dir}/FAILED"
    fi
    # Allow metrics to stabilise after load test.
    sleep 5
  fi

  # ── Capture placement ──────────────────────────────────────────────────────
  log "Capturing placement..."
  kubectl get pods -n default --context "${CONTEXT}" -o wide \
    > "${run_dir}/placement.txt"
  kubectl get pods -n default --context "${CONTEXT}" -o json \
    > "${run_dir}/pods.json"

  # ── Capture events ─────────────────────────────────────────────────────────
  log "Capturing events..."
  kubectl get events -n default --context "${CONTEXT}" \
    --sort-by=.metadata.creationTimestamp \
    > "${run_dir}/events.txt"
  kubectl get events -n default --context "${CONTEXT}" -o json \
    > "${run_dir}/events.json"

  # ── Capture scheduler logs ─────────────────────────────────────────────────
  log "Capturing scheduler logs..."
  kubectl logs -n kube-system \
    -l app.kubernetes.io/name=energy-aware-scheduler \
    --context "${CONTEXT}" \
    --since-time="${start_time}" \
    > "${run_dir}/scoring.txt" 2>&1 || true

  # ── Capture Prometheus utilisation ────────────────────────────────────────
  log "Capturing Prometheus node utilisation..."
  query_prometheus "${run_dir}/utilization.json"

  # ── Compute scheduling latency ─────────────────────────────────────────────
  log "Computing scheduling latency..."
  compute_latency \
    "${run_dir}/pods.json" \
    "${run_dir}/events.json" \
    "${run_dir}/latency.txt"

  log "Completed Run ${run_num} for ${scenario} (${sched})."

  # Clean up manifest and namespace.
  kubectl delete -f "${manifest}" --context "${CONTEXT}" \
    --timeout=60s 2>/dev/null || true
  cleanup_namespace
  sleep 5
}

# ── Main Loop ─────────────────────────────────────────────────────────────────
log "Initialising Week 6 experiment campaign (5 runs per scenario/scheduler)..."
mkdir -p "${RESULTS_DIR}"

for scen in "${SCENARIOS[@]}"; do
  for sched in "${SCHEDULERS[@]}"; do
    for run in "${RUNS[@]}"; do
      run_single_experiment "${scen}" "${sched}" "${run}"
    done
  done
done

log "All 40 experimental runs completed."
log "Results saved under ${RESULTS_DIR}/"
log ""
log "Next step: python3 scripts/analyze_results.py to produce results/week6/summary.csv"
