#!/usr/bin/env bash
# =============================================================================
# scripts/setup-cluster.sh
# =============================================================================
# Purpose:  Create the 'energy' KIND cluster for the Energy-Aware Scheduler
#           B.Tech project.
#
# Usage:    bash scripts/setup-cluster.sh
#
# What it does:
#   1. Checks that KIND is available.
#   2. Checks whether the 'energy' cluster already exists.
#   3. If the cluster already exists, skips creation (idempotent).
#   4. If not, creates the cluster using cluster/kind-config.yaml.
#   5. Verifies the cluster by listing all nodes.
#
# How to verify it worked:
#   kubectl get nodes
#   You should see 4 nodes: 1 control-plane + 3 workers, all eventually Ready.
#
# Expected total time: 2-5 minutes depending on image download speed.
# =============================================================================

set -euo pipefail

CLUSTER_NAME="energy"
CONFIG_FILE="cluster/kind-config.yaml"

# -------------------------------------------------------
# Helper: print with timestamp
# -------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "======================================================"
log "  Energy-Aware Scheduler — Cluster Setup"
log "======================================================"

# -------------------------------------------------------
# Step 1: Verify KIND is installed
# -------------------------------------------------------
if ! command -v kind &>/dev/null; then
  echo "ERROR: 'kind' is not installed or not in PATH."
  echo "Install guide: https://kind.sigs.k8s.io/docs/user/quick-start/"
  exit 1
fi

log "Found kind: $(kind version)"

# -------------------------------------------------------
# Step 2: Check if the cluster already exists
# -------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
  log "To delete and recreate it, run: bash scripts/teardown.sh"
else
  # -------------------------------------------------------
  # Step 3: Verify the config file exists
  # -------------------------------------------------------
  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    echo "Run this script from the project root directory."
    exit 1
  fi

  log "Creating KIND cluster '${CLUSTER_NAME}' using ${CONFIG_FILE} ..."
  log "This may take 2-5 minutes on first run (pulls node images)."

  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${CONFIG_FILE}"

  log "Cluster creation complete."
fi

# -------------------------------------------------------
# Step 4: Switch kubectl context to the new cluster
# -------------------------------------------------------
log "Setting kubectl context to kind-${CLUSTER_NAME} ..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# -------------------------------------------------------
# Step 5: Wait for nodes to become Ready
# -------------------------------------------------------
log "Waiting for all nodes to become Ready (timeout: 120s) ..."
kubectl wait --for=condition=Ready node --all --timeout=120s \
  --context "kind-${CLUSTER_NAME}"

# -------------------------------------------------------
# Step 6: Display node list
# -------------------------------------------------------
log "======================================================"
log "  Cluster nodes:"
log "======================================================"
kubectl get nodes --context "kind-${CLUSTER_NAME}" -o wide

log ""
log "SUCCESS: Cluster '${CLUSTER_NAME}' is ready."
log ""
log "Next steps:"
log "  1. Label the worker nodes:  bash scripts/label-nodes.sh"
log "  2. Install monitoring:      bash scripts/install-monitoring.sh"
