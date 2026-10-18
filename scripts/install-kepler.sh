#!/usr/bin/env bash
# =============================================================================
# scripts/install-kepler.sh
# =============================================================================
# Purpose:  Document Kepler's status on the KIND 'energy' cluster and
#           install it if the environment supports it.
#
# IMPORTANT DISCLAIMER
# --------------------
# KIND runs Kubernetes nodes as Docker containers on a Windows/WSL2 host.
# Kepler uses eBPF to collect kernel-level power/energy estimates.
# eBPF requires:
#   1. The host kernel to expose /proc and kernel headers.
#   2. The KIND nodes to be configured with extraMounts for /proc and /usr/src.
#
# The existing 'energy' KIND cluster was created WITHOUT these extraMounts
# (see cluster/kind-config.yaml — it has no extraMounts).
#
# Therefore:
#   - Kepler CANNOT be installed on the existing cluster without recreating it.
#   - This script documents that limitation and falls back to node-exporter.
#   - If you recreate the cluster with the extraMounts config (see below),
#     re-run this script to install Kepler.
#
# To recreate the cluster WITH Kepler support, replace cluster/kind-config.yaml
# with the version in docs/kind-config-kepler.yaml, then run:
#   bash scripts/teardown.sh
#   bash scripts/setup-cluster.sh
#   bash scripts/label-nodes.sh
#   bash scripts/install-monitoring.sh
#   bash scripts/install-kepler.sh
#
# POWER MEASUREMENT HONESTY NOTE
# --------------------------------
# Even with Kepler installed on KIND:
#   - Metrics are ESTIMATES based on resource usage and power models.
#   - They are NOT physical hardware measurements.
#   - Real RAPL counters require bare-metal or specific VM support.
#   - In your B.Tech project, always describe Kepler values on KIND as
#     "estimated power consumption" not "measured power consumption".
# =============================================================================

set -euo pipefail

CONTEXT="kind-energy"
CLUSTER_NAME="energy"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "======================================================"
log "  Kepler Installation Check"
log "======================================================"

# -------------------------------------------------------
# Check: Does the existing cluster have /proc mounted?
# -------------------------------------------------------
log "Checking whether KIND nodes have /proc-host mounted ..."

CONTROL_PLANE_NODE=$(kind get nodes --name "${CLUSTER_NAME}" 2>/dev/null | grep 'control-plane' | head -1 || true)

if [ -z "${CONTROL_PLANE_NODE}" ]; then
  echo "ERROR: KIND cluster '${CLUSTER_NAME}' not found or not running."
  echo "Run: bash scripts/setup-cluster.sh"
  exit 1
fi

HAS_PROC_MOUNT=$(docker inspect "${CONTROL_PLANE_NODE}" 2>/dev/null \
  | grep -c 'proc-host' || true)

if [ "${HAS_PROC_MOUNT}" -eq 0 ]; then
  log ""
  log "======================================================"
  log "  RESULT: Kepler CANNOT be installed on this cluster."
  log "======================================================"
  log ""
  log "  Reason:"
  log "  The KIND cluster was created without the /proc and /usr/src"
  log "  host mounts that Kepler's eBPF programs require."
  log ""
  log "  Current cluster/kind-config.yaml does not include extraMounts."
  log "  The file docs/kind-config-kepler.yaml contains the corrected"
  log "  cluster config that supports Kepler."
  log ""
  log "  FALLBACK:"
  log "  Use node-exporter metrics (already running via kube-prometheus-stack)."
  log "  See docs/metrics.md for verified PromQL queries."
  log ""
  log "  TO ENABLE KEPLER (requires cluster recreation):"
  log "  1. cp docs/kind-config-kepler.yaml cluster/kind-config.yaml"
  log "  2. bash scripts/teardown.sh"
  log "  3. bash scripts/setup-cluster.sh"
  log "  4. bash scripts/label-nodes.sh"
  log "  5. bash scripts/install-monitoring.sh"
  log "  6. bash scripts/install-kepler.sh"
  log ""
  exit 0
fi

# -------------------------------------------------------
# Cluster supports Kepler — install via Helm
# -------------------------------------------------------
log "KIND nodes have /proc-host mounted — proceeding with Kepler installation."
log ""

# Add the Kepler Helm repository.
log "Adding Kepler Helm repository ..."
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart 2>/dev/null || true
helm repo update kepler

log "Installing Kepler ..."
helm upgrade --install kepler kepler/kepler \
  --namespace kepler \
  --create-namespace \
  --kube-context "${CONTEXT}" \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.labels.release=kube-prometheus-stack \
  --wait \
  --timeout 5m

log "Waiting for Kepler pods to be Ready ..."
kubectl wait pod \
  --all \
  --for=condition=Ready \
  --namespace kepler \
  --context "${CONTEXT}" \
  --timeout=120s

log ""
kubectl get pods -n kepler --context "${CONTEXT}"

log ""
log "SUCCESS: Kepler is installed."
log ""
log "Verify Kepler metrics in Prometheus (after ~60s scrape interval):"
log "  http://localhost:9090/graph?g0.expr=kepler_container_joules_total"
log ""
log "NOTE: Kepler values on KIND are power estimates, NOT hardware measurements."
