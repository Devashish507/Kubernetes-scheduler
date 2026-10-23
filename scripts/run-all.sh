#!/usr/bin/env bash
# =============================================================================
# scripts/run-all.sh
# One-shot script: cluster setup → monitoring → scheduler build+deploy →
# run all experiments → analysis → delta computation.
#
# Usage:
#   bash scripts/run-all.sh              # full run including setup
#   bash scripts/run-all.sh --skip-setup # skip cluster/monitoring/build steps
#
# Prerequisites (must already be met):
#   - Docker Desktop running with WSL2 integration
#   - kind, kubectl, helm, go >= 1.26, python3 in PATH
#   - All commands run inside WSL2 Ubuntu from the project root
#
# What it does:
#   1. (Unless --skip-setup) Create KIND cluster "energy"
#   2. (Unless --skip-setup) Label worker nodes with power profiles
#   3. (Unless --skip-setup) Install kube-prometheus-stack
#   4. (Unless --skip-setup) Build and load energy-aware-scheduler image
#   5. (Unless --skip-setup) Deploy energy-aware-scheduler manifests
#   6. Run weight tuning grid search (scripts/tune_weights.py)
#   7. Apply tuned weights + restart scheduler
#   8. Run all 40 experiments (scripts/run-experiments.sh)
#   9. Analyse results + generate charts (scripts/analyze_results.py)
#  10. Compute deltas (scripts/compute_deltas.py)
#
# Exit codes:
#   0 — all steps completed successfully
#   1 — a step failed; the failing step is printed
# =============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="kind-energy"
SKIP_SETUP=false

log() { echo ""; echo ">>> [$(date '+%H:%M:%S')] $*"; echo ""; }
step() { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  STEP: $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo ""; }

# Parse flags
for arg in "$@"; do
  case "${arg}" in
    --skip-setup) SKIP_SETUP=true ;;
    *) echo "Unknown flag: ${arg}"; exit 1 ;;
  esac
done

cd "${BASE_DIR}"

log "Energy-Aware Scheduler — Full Run Pipeline"
log "Base directory: ${BASE_DIR}"
log "Skip setup: ${SKIP_SETUP}"

# ── Step 1-5: Infrastructure setup ───────────────────────────────────────────
if [ "${SKIP_SETUP}" = "false" ]; then

  step "1/10 — Create KIND cluster"
  bash scripts/setup-cluster.sh
  echo "✓ Cluster ready"

  step "2/10 — Label worker nodes with power profiles"
  bash scripts/label-nodes.sh
  echo "✓ Nodes labeled"

  step "3/10 — Install monitoring (kube-prometheus-stack)"
  bash scripts/install-monitoring.sh
  echo "✓ Monitoring ready"

  step "4/10 — Build and load energy-aware-scheduler image"
  bash scripts/build-scheduler.sh
  echo "✓ Image loaded into KIND"

  step "5/10 — Deploy energy-aware-scheduler manifests"
  bash scripts/deploy-scheduler.sh
  echo "✓ Scheduler deployed"

else
  log "Skipping setup steps 1-5 (--skip-setup specified)"
  log "Verifying cluster is reachable..."
  kubectl cluster-info --context "${CONTEXT}" >/dev/null
  echo "✓ Cluster reachable"
fi

# ── Step 6: Weight tuning ─────────────────────────────────────────────────────
step "6/10 — Weight tuning grid search"
python3 scripts/tune_weights.py
echo "✓ Tuning complete; results/week6/tuning.csv written"

# ── Step 7: Apply tuned weights ───────────────────────────────────────────────
step "7/10 — Apply tuned ConfigMap weights and restart scheduler"
kubectl apply --context "${CONTEXT}" -f scheduler/manifests/configmap.yaml
kubectl rollout restart deployment/energy-aware-scheduler \
  -n kube-system --context "${CONTEXT}"
kubectl rollout status deployment/energy-aware-scheduler \
  -n kube-system --context "${CONTEXT}" --timeout=120s
echo "✓ Scheduler restarted with tuned weights"

# ── Step 8: Experiments ───────────────────────────────────────────────────────
step "8/10 — Run all 40 experiments (Scenarios 1-4 × 2 schedulers × 5 runs)"
bash scripts/run-experiments.sh
echo "✓ Experiments complete; results under results/week6/"

# ── Step 9: Analysis ──────────────────────────────────────────────────────────
step "9/10 — Analyse results and generate charts"
python3 scripts/analyze_results.py
echo "✓ summary.csv and charts written to results/week6/"

# ── Step 10: Deltas ───────────────────────────────────────────────────────────
step "10/10 — Compute percent-change deltas"
python3 scripts/compute_deltas.py
echo "✓ deltas.csv written to results/week7/"

# ── Final summary ─────────────────────────────────────────────────────────────
log "Pipeline complete."
echo "Output locations:"
echo "  results/week6/summary.csv      — main results with mean and std"
echo "  results/week6/tuning.csv       — weight grid search"
echo "  results/week6/charts/          — PNG charts"
echo "  results/week7/deltas.csv       — percent-change deltas"
echo ""
echo "To view Grafana:"
echo "  bash scripts/port-forward.sh"
echo "  open http://localhost:3000"
