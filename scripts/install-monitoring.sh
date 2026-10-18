#!/usr/bin/env bash
# =============================================================================
# scripts/install-monitoring.sh
# =============================================================================
# Purpose:  Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
#           into the 'monitoring' namespace of the 'energy' KIND cluster.
#
# Usage:    bash scripts/install-monitoring.sh
#
# Chart:    prometheus-community/kube-prometheus-stack
# Version:  91.5.2  (verified on Artifact Hub, September 2026)
# Values:   monitoring/values.yaml
#
# What it does:
#   1. Verifies required tools (helm, kubectl).
#   2. Adds/updates the prometheus-community Helm repository.
#   3. Creates the 'monitoring' namespace if it does not exist.
#   4. Installs or upgrades the chart.
#   5. Waits for all pods to become Ready.
#   6. Displays pod and service status.
#
# How to verify:
#   kubectl get pods -n monitoring
#   kubectl get svc  -n monitoring
# =============================================================================

set -euo pipefail

RELEASE_NAME="kube-prometheus-stack"
NAMESPACE="monitoring"
CHART="prometheus-community/kube-prometheus-stack"
CHART_VERSION="91.5.2"
VALUES_FILE="monitoring/values.yaml"
CONTEXT="kind-energy"

# -------------------------------------------------------
# Helper: print with timestamp
# -------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "======================================================"
log "  Energy-Aware Scheduler — Install Monitoring Stack"
log "======================================================"

# -------------------------------------------------------
# Step 1: Verify required tools
# -------------------------------------------------------
for tool in helm kubectl; do
  if ! command -v "${tool}" &>/dev/null; then
    echo "ERROR: '${tool}' is not installed or not in PATH."
    exit 1
  fi
done

log "helm version: $(helm version --short)"
log "kubectl context: ${CONTEXT}"

# -------------------------------------------------------
# Step 2: Verify values file exists
# -------------------------------------------------------
if [ ! -f "${VALUES_FILE}" ]; then
  echo "ERROR: Values file not found: ${VALUES_FILE}"
  echo "Run this script from the project root directory."
  exit 1
fi

# -------------------------------------------------------
# Step 3: Add / update the Helm repository
# -------------------------------------------------------
log "Adding/updating prometheus-community Helm repository ..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

# -------------------------------------------------------
# Step 4: Create the monitoring namespace (idempotent)
# -------------------------------------------------------
log "Ensuring namespace '${NAMESPACE}' exists ..."
kubectl create namespace "${NAMESPACE}" \
  --context "${CONTEXT}" \
  --dry-run=client -o yaml | kubectl apply --context "${CONTEXT}" -f -

# -------------------------------------------------------
# Step 5: Install or upgrade the Helm release
# -------------------------------------------------------
log "Installing/upgrading ${RELEASE_NAME} chart ${CHART_VERSION} ..."
log "This may take several minutes on first install."

helm upgrade --install "${RELEASE_NAME}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --kube-context "${CONTEXT}" \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

log "Helm install/upgrade complete."

# -------------------------------------------------------
# Step 6: Wait for all monitoring pods to be Ready
# -------------------------------------------------------
log "Waiting for all pods in '${NAMESPACE}' to become Ready ..."
kubectl wait pod \
  --all \
  --for=condition=Ready \
  --namespace "${NAMESPACE}" \
  --context "${CONTEXT}" \
  --timeout=300s

# -------------------------------------------------------
# Step 7: Display status
# -------------------------------------------------------
log ""
log "======================================================"
log "  Pods in namespace '${NAMESPACE}':"
log "======================================================"
kubectl get pods -n "${NAMESPACE}" --context "${CONTEXT}"

log ""
log "======================================================"
log "  Services in namespace '${NAMESPACE}':"
log "======================================================"
kubectl get svc -n "${NAMESPACE}" --context "${CONTEXT}"

# -------------------------------------------------------
# Step 7: Provision the Grafana comparison dashboard
# -------------------------------------------------------
log ""
log "Provisioning Grafana scheduler-comparison dashboard ..."
DASHBOARD_JSON="monitoring/dashboards/scheduler-comparison.json"
CONFIGMAP_TEMPLATE="monitoring/dashboards/dashboard-configmap.yaml"

if [ -f "${DASHBOARD_JSON}" ] && [ -f "${CONFIGMAP_TEMPLATE}" ]; then
  # Build the ConfigMap by embedding the JSON with proper indentation (2 spaces).
  # The grafana sidecar reads the value of the key as a plain JSON string.
  {
    cat "${CONFIGMAP_TEMPLATE}"
    # Indent each JSON line by 4 spaces (YAML multiline literal block scalar)
    sed 's/^/    /' "${DASHBOARD_JSON}"
  } | kubectl apply --context "${CONTEXT}" -n "${NAMESPACE}" -f -
  log "Dashboard ConfigMap applied. Grafana sidecar will pick it up within ~30s."
else
  log "WARNING: Dashboard JSON or ConfigMap template not found — skipping."
fi

log ""
log "SUCCESS: Monitoring stack is installed and ready."
log ""
log "Next step: bash scripts/port-forward.sh"
log "           Then open http://localhost:3000 (Grafana)"
log "           and  http://localhost:9090 (Prometheus)"
log ""
log "Grafana dashboard: Energy-Aware Scheduler — Comparison"
log "  (visible in Grafana under folder 'Energy Scheduler')"
