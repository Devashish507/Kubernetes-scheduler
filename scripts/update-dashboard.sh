#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${BASE_DIR}"

DASHBOARD_JSON="monitoring/dashboards/scheduler-comparison.json"
CONFIGMAP_TEMPLATE="monitoring/dashboards/dashboard-configmap.yaml"
CONTEXT="kind-energy"
NAMESPACE="monitoring"

echo "Applying updated Grafana dashboard to cluster..."
{
  cat "${CONFIGMAP_TEMPLATE}"
  sed 's/^/    /' "${DASHBOARD_JSON}"
} | kubectl apply --context "${CONTEXT}" -n "${NAMESPACE}" -f -

echo "✓ Dashboard ConfigMap updated. Grafana sidecar will refresh it in ~15-30s."
