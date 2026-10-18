#!/usr/bin/env bash
# =============================================================================
# scripts/teardown.sh
# =============================================================================
# Purpose:  Delete the 'energy' KIND cluster.
#
# Usage:    bash scripts/teardown.sh
#
# What it does:
#   1. Checks whether the 'energy' cluster exists.
#   2. If it exists, deletes it cleanly.
#   3. If it does not exist, prints a message and exits without error.
#
# Safety:
#   - Only deletes the cluster named 'energy'.
#   - Does NOT touch any other KIND clusters on your system.
#   - Prints exactly what it is about to delete before doing so.
#
# How to verify it worked:
#   kind get clusters
#   The 'energy' cluster should no longer appear.
# =============================================================================

set -euo pipefail

CLUSTER_NAME="energy"

# -------------------------------------------------------
# Helper: print with timestamp
# -------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "======================================================"
log "  Energy-Aware Scheduler — Cluster Teardown"
log "======================================================"

# -------------------------------------------------------
# Step 1: Verify KIND is installed
# -------------------------------------------------------
if ! command -v kind &>/dev/null; then
  echo "ERROR: 'kind' is not installed or not in PATH."
  exit 1
fi

# -------------------------------------------------------
# Step 2: Check if the cluster exists
# -------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "Found cluster '${CLUSTER_NAME}'. Deleting it now ..."
  log ""
  log "  This will permanently delete the cluster and all its workloads."
  log "  Only the 'energy' cluster is affected. Other clusters are untouched."
  log ""
  kind delete cluster --name "${CLUSTER_NAME}"
  log "Cluster '${CLUSTER_NAME}' has been deleted."
else
  log "Cluster '${CLUSTER_NAME}' does not exist. Nothing to delete."
fi

log ""
log "To recreate the cluster: bash scripts/setup-cluster.sh"
