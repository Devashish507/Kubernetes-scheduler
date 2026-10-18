#!/usr/bin/env bash
# =============================================================================
# scripts/label-nodes.sh
# =============================================================================
# Purpose:  Apply simulated power-profile labels to the three KIND worker nodes.
#
# Usage:    bash scripts/label-nodes.sh
#
# IMPORTANT DISCLAIMER
# --------------------
# KIND runs Kubernetes nodes as Docker containers on your local machine.
# These labels represent SIMULATED power characteristics for the purpose of
# developing and evaluating the scheduling algorithms. They are NOT real
# hardware power measurements. No actual wattage values are measured here.
#
# Label Schema
# ------------
# Domain:    energy.project/
# Labels applied:
#
#   energy.project/power-profile  — Human-readable tier name.
#                                   Values: efficient | medium | power-hungry
#
#   energy.project/p-idle         — Simulated idle power (watts, as a string).
#                                   Represents estimated power when node is idle.
#
#   energy.project/p-max          — Simulated peak power (watts, as a string).
#                                   Represents estimated power at 100% CPU load.
#
# Node assignments (KIND assigns worker names automatically):
#
#   energy-worker    → power-profile=efficient   p-idle=20W  p-max=60W
#   energy-worker2   → power-profile=medium      p-idle=40W  p-max=120W
#   energy-worker3   → power-profile=power-hungry p-idle=80W p-max=200W
#
# These values are illustrative. They serve as scheduling input for the
# custom energy-aware scorer in later project phases.
#
# How to verify:
#   kubectl get nodes --show-labels
#   kubectl get nodes -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
# =============================================================================

set -euo pipefail

CONTEXT="kind-energy"

# -------------------------------------------------------
# Helper: print with timestamp
# -------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "======================================================"
log "  Energy-Aware Scheduler — Node Labeling"
log "======================================================"
log ""
log "DISCLAIMER: Labels represent SIMULATED power profiles."
log "            They are NOT real hardware power measurements."
log ""

# -------------------------------------------------------
# Step 1: Verify kubectl is available
# -------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH."
  exit 1
fi

# -------------------------------------------------------
# Step 2: Verify the expected worker nodes exist
# -------------------------------------------------------
EXPECTED_WORKERS=("energy-worker" "energy-worker2" "energy-worker3")
MISSING=()

for node in "${EXPECTED_WORKERS[@]}"; do
  if ! kubectl get node "${node}" --context "${CONTEXT}" &>/dev/null; then
    MISSING+=("${node}")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: The following expected worker nodes were not found:"
  for m in "${MISSING[@]}"; do
    echo "  - ${m}"
  done
  echo ""
  echo "Make sure the cluster is running:"
  echo "  bash scripts/setup-cluster.sh"
  echo ""
  echo "Then verify nodes:"
  echo "  kubectl get nodes --context kind-energy"
  exit 1
fi

log "All expected worker nodes are present."

# -------------------------------------------------------
# Step 3: Apply labels to each worker node
# -------------------------------------------------------

log ""
log "Labeling energy-worker → efficient (p-idle=20W, p-max=60W) ..."
kubectl label node energy-worker \
  --context "${CONTEXT}" \
  --overwrite \
  energy.project/power-profile=efficient \
  energy.project/p-idle=20W \
  energy.project/p-max=60W

log "Labeling energy-worker2 → medium (p-idle=40W, p-max=120W) ..."
kubectl label node energy-worker2 \
  --context "${CONTEXT}" \
  --overwrite \
  energy.project/power-profile=medium \
  energy.project/p-idle=40W \
  energy.project/p-max=120W

log "Labeling energy-worker3 → power-hungry (p-idle=80W, p-max=200W) ..."
kubectl label node energy-worker3 \
  --context "${CONTEXT}" \
  --overwrite \
  energy.project/power-profile=power-hungry \
  energy.project/p-idle=80W \
  energy.project/p-max=200W

# -------------------------------------------------------
# Step 4: Display resulting labels
# -------------------------------------------------------
log ""
log "======================================================"
log "  Resulting node labels (energy.project/* columns):"
log "======================================================"
kubectl get nodes \
  --context "${CONTEXT}" \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max

log ""
log "SUCCESS: Power profile labels applied."
log ""
log "To view all labels: kubectl get nodes --show-labels --context kind-energy"
