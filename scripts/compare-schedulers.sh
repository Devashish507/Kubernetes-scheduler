#!/usr/bin/env bash
set -euo pipefail

CONTEXT="kind-energy"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

mkdir -p results/week3

run_test() {
  local name=$1
  local yaml_file=$2

  log "Running test: ${name}"
  
  # Delete if exists
  kubectl delete -f "${yaml_file}" --context "${CONTEXT}" --ignore-not-found=true 2>/dev/null || true
  sleep 2

  start_time=$(date +%s)
  
  kubectl apply -f "${yaml_file}" --context "${CONTEXT}"

  # Wait for pods to schedule and become ready
  log "Waiting for pods to schedule..."
  
  # Extract type (deployment or job)
  if grep -q "kind: Deployment" "${yaml_file}"; then
      kubectl wait --for=condition=Available deployment/$(grep "name:" "${yaml_file}" | head -1 | awk '{print $2}') --context "${CONTEXT}" --timeout=120s
  else
      kubectl wait --for=condition=Complete job/$(grep "name:" "${yaml_file}" | head -1 | awk '{print $2}') --context "${CONTEXT}" --timeout=120s || true
  fi

  end_time=$(date +%s)
  latency=$((end_time - start_time))
  
  # Capture placement
  log "Capturing placement..."
  kubectl get pods -o wide --context "${CONTEXT}" > "results/week3/${name}-placement.txt"
  
  # Capture metrics (Prometheus)
  log "Capturing utilization metrics..."
  # Simple top as fallback
  kubectl top nodes --context "${CONTEXT}" > "results/week3/${name}-utilization.txt" 2>/dev/null || echo "kubectl top failed" > "results/week3/${name}-utilization.txt"
  
  # Record latency
  echo "Latency (deploy to ready/complete): ${latency} seconds" > "results/week3/${name}-latency.txt"
  
  log "Test ${name} complete."
  
  # Cleanup
  kubectl delete -f "${yaml_file}" --context "${CONTEXT}" --ignore-not-found=true 2>/dev/null || true
  sleep 5
}

run_test "latency-default" "workloads/nginx-default.yaml"
run_test "latency-energy-aware" "workloads/nginx-energy-aware.yaml"
run_test "batch-default" "workloads/batch-default.yaml"
run_test "batch-energy-aware" "workloads/batch-energy-aware.yaml"

log "All tests completed. Results saved in results/week3/"
