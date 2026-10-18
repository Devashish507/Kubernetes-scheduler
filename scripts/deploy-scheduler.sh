#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-scheduler.sh
# =============================================================================
# Purpose:  Apply all Kubernetes manifests for the energy-aware-scheduler.
#
# Usage:    bash scripts/deploy-scheduler.sh
#
# What it does:
#   1. Applies ServiceAccount, RBAC, ConfigMap, and Deployment in order.
#   2. Waits for the scheduler pod to become Ready.
#   3. Prints the scheduler pod logs so you can verify EnergyAware is loaded.
# =============================================================================

set -euo pipefail

CONTEXT="kind-energy"
MANIFESTS_DIR="scheduler/manifests"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "======================================================"
log "  Energy-Aware Scheduler — Deploy"
log "======================================================"

if [ ! -d "${MANIFESTS_DIR}" ]; then
  echo "ERROR: Manifests directory not found: ${MANIFESTS_DIR}"
  echo "Run from the project root directory."
  exit 1
fi

log "Applying manifests from ${MANIFESTS_DIR}/ ..."
kubectl apply --context "${CONTEXT}" -f "${MANIFESTS_DIR}/serviceaccount.yaml"
kubectl apply --context "${CONTEXT}" -f "${MANIFESTS_DIR}/rbac.yaml"
kubectl apply --context "${CONTEXT}" -f "${MANIFESTS_DIR}/configmap.yaml"
kubectl apply --context "${CONTEXT}" -f "${MANIFESTS_DIR}/deployment.yaml"

log "Waiting for energy-aware-scheduler pod to be Ready (timeout: 120s) ..."
kubectl rollout status deployment/energy-aware-scheduler \
  -n kube-system \
  --context "${CONTEXT}" \
  --timeout=120s

log ""
log "======================================================"
log "  Scheduler pod status:"
log "======================================================"
kubectl get pods -n kube-system --context "${CONTEXT}" \
  -l app.kubernetes.io/name=energy-aware-scheduler

log ""
log "======================================================"
log "  Last 30 lines of scheduler logs:"
log "======================================================"
POD=$(kubectl get pods -n kube-system --context "${CONTEXT}" \
  -l app.kubernetes.io/name=energy-aware-scheduler \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "${POD}" ]; then
  kubectl logs "${POD}" -n kube-system --context "${CONTEXT}" --tail=30 || true
fi

log ""
log "SUCCESS: energy-aware-scheduler is deployed."
log ""
log "To see EnergyAware scoring logs when a pod is scheduled:"
log "  kubectl logs -f ${POD:-<scheduler-pod>} -n kube-system --context kind-energy | grep -i energyaware"
