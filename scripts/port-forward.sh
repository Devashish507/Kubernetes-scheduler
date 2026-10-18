#!/usr/bin/env bash
# =============================================================================
# scripts/port-forward.sh
# =============================================================================
# Purpose:  Forward Grafana and Prometheus service ports to localhost so you
#           can access the monitoring UIs from your Windows browser via
#           the WSL2 network.
#
# Usage:    bash scripts/port-forward.sh
#
# Access:
#   Grafana    → http://localhost:3000
#   Prometheus → http://localhost:9090
#
# How to stop:
#   Press Ctrl+C in the terminal where this script is running.
#   Both port-forward processes will be stopped automatically.
#
# Service name discovery:
#   The script uses 'kubectl get svc' to dynamically discover the correct
#   service names rather than hard-coding them.  If the chart is upgraded
#   and service names change, the script will still find the right services
#   as long as they carry 'grafana' or 'prometheus' in their name and are
#   of the expected type.
#
# Note on WSL2 + Windows:
#   Port-forwarded ports in WSL2 are generally accessible from Windows at
#   http://localhost:<port> when Docker Desktop WSL2 integration is enabled.
#   If they are not reachable, try http://$(hostname -I | awk '{print $1}'):<port>
# =============================================================================

set -euo pipefail

NAMESPACE="monitoring"
CONTEXT="kind-energy"

GRAFANA_LOCAL_PORT=3000
PROMETHEUS_LOCAL_PORT=9090

# -------------------------------------------------------
# Helper: print with timestamp
# -------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "======================================================"
log "  Energy-Aware Scheduler — Port Forwarding"
log "======================================================"

# -------------------------------------------------------
# Step 1: Verify required tools
# -------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH."
  exit 1
fi

# -------------------------------------------------------
# Step 2: Verify monitoring namespace exists
# -------------------------------------------------------
if ! kubectl get namespace "${NAMESPACE}" --context "${CONTEXT}" &>/dev/null; then
  echo "ERROR: Namespace '${NAMESPACE}' does not exist."
  echo "Run: bash scripts/install-monitoring.sh"
  exit 1
fi

# -------------------------------------------------------
# Step 3: Discover the Grafana service name
# -------------------------------------------------------
log "Discovering Grafana service in namespace '${NAMESPACE}' ..."
GRAFANA_SVC=$(kubectl get svc -n "${NAMESPACE}" --context "${CONTEXT}" \
  -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' \
  | grep -i 'grafana' \
  | grep -v 'operated\|headless' \
  | head -n1 || true)

if [ -z "${GRAFANA_SVC}" ]; then
  echo "ERROR: Could not find a Grafana service in namespace '${NAMESPACE}'."
  echo "Check: kubectl get svc -n monitoring"
  exit 1
fi

log "Found Grafana service: ${GRAFANA_SVC}"

# -------------------------------------------------------
# Step 4: Discover the Prometheus service name
# -------------------------------------------------------
log "Discovering Prometheus service in namespace '${NAMESPACE}' ..."
# NOTE: Every service in kube-prometheus-stack contains "prometheus" in its
# name (they are all prefixed kube-prometheus-stack-*).  We must therefore
# explicitly exclude every service that is NOT the main Prometheus ClusterIP.
PROMETHEUS_SVC=$(kubectl get svc -n "${NAMESPACE}" --context "${CONTEXT}" \
  -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' \
  | grep -i 'prometheus' \
  | grep -v 'grafana\|operator\|alertmanager\|node-exporter\|state-metrics\|operated' \
  | head -n1 || true)

if [ -z "${PROMETHEUS_SVC}" ]; then
  echo "ERROR: Could not find a Prometheus service in namespace '${NAMESPACE}'."
  echo "Check: kubectl get svc -n monitoring"
  exit 1
fi

log "Found Prometheus service: ${PROMETHEUS_SVC}"

# -------------------------------------------------------
# Step 5: Start port forwarding in background
# -------------------------------------------------------
log ""
log "Starting port forwarding ..."

# Start Grafana port-forward in background
kubectl port-forward \
  --context "${CONTEXT}" \
  -n "${NAMESPACE}" \
  "svc/${GRAFANA_SVC}" \
  "${GRAFANA_LOCAL_PORT}:80" &
PF_GRAFANA_PID=$!

# Start Prometheus port-forward in background
kubectl port-forward \
  --context "${CONTEXT}" \
  -n "${NAMESPACE}" \
  "svc/${PROMETHEUS_SVC}" \
  "${PROMETHEUS_LOCAL_PORT}:9090" &
PF_PROMETHEUS_PID=$!

# -------------------------------------------------------
# Step 6: Wait a moment and verify the processes started
# -------------------------------------------------------
sleep 2
if ! kill -0 "${PF_GRAFANA_PID}" 2>/dev/null; then
  echo "ERROR: Grafana port-forward process failed to start."
  exit 1
fi
if ! kill -0 "${PF_PROMETHEUS_PID}" 2>/dev/null; then
  echo "ERROR: Prometheus port-forward process failed to start."
  kill "${PF_GRAFANA_PID}" 2>/dev/null || true
  exit 1
fi

# -------------------------------------------------------
# Step 7: Print access info
# -------------------------------------------------------
log ""
log "======================================================"
log "  Port forwarding is active:"
log ""
log "  Grafana    → http://localhost:${GRAFANA_LOCAL_PORT}"
log "              Username: admin"
log "              Password: retrieve with:"
log "              kubectl get secret kube-prometheus-stack-grafana \\"
log "                -n monitoring \\"
log "                -o jsonpath=\"{.data.admin-password}\" | base64 --decode"
log ""
log "  Prometheus → http://localhost:${PROMETHEUS_LOCAL_PORT}"
log ""
log "  Press Ctrl+C to stop port forwarding."
log "======================================================"

# -------------------------------------------------------
# Step 8: Clean up background processes on exit
# -------------------------------------------------------
cleanup() {
  log ""
  log "Stopping port forwarding ..."
  kill "${PF_GRAFANA_PID}"    2>/dev/null || true
  kill "${PF_PROMETHEUS_PID}" 2>/dev/null || true
  log "Port forwarding stopped."
}
trap cleanup EXIT INT TERM

# -------------------------------------------------------
# Wait indefinitely for Ctrl+C
# -------------------------------------------------------
wait
