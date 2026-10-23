#!/usr/bin/env bash
# =============================================================================
# scripts/demo.sh
# Week 7 – 5-to-7 minute demo runner with automatic pauses.
#
# Usage:
#   bash scripts/demo.sh
#
# Each step pauses and waits for ENTER so the presenter controls the pace.
# Pre-conditions (must be met before running):
#   - KIND cluster "energy" is running
#   - energy-aware-scheduler Deployment is Ready
#   - kube-prometheus-stack is running in the monitoring namespace
#   - Grafana is port-forwarded on localhost:3000
#     (run 'bash scripts/port-forward.sh' in a separate terminal first)
# =============================================================================
set -euo pipefail

CONTEXT="kind-energy"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

pause() {
  echo ""
  echo -e "${YELLOW}▶  Press ENTER to continue to the next step...${RESET}"
  read -r
}

banner() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $*${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

cd "${BASE_DIR}"

# ── Step 1: Nodes and power labels ────────────────────────────────────────────
banner "STEP 1/6 — Cluster nodes and simulated power labels"
echo "Showing the 4-node Kind cluster and per-node power-profile labels."
echo "Labels are SIMULATED — no real hardware sensors are used."
echo ""
kubectl get nodes --context "${CONTEXT}" \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max
pause

# ── Step 2: Grafana ───────────────────────────────────────────────────────────
banner "STEP 2/6 — Grafana dashboard"
echo "Open your browser at: http://localhost:3000"
echo "Dashboard: 'Energy-Aware Scheduler — Comparison'"
echo ""
echo "Key panels to show:"
echo "  • Per-Node CPU Utilization (%) — timeseries"
echo "  • Per-Node Estimated Power (W) — stat panel (colour-coded by tier)"
echo "  • Total Estimated Cluster Power (W) — stat"
echo "  • Pods per Node — donut chart"
echo ""
echo "(Grafana must be port-forwarded: bash scripts/port-forward.sh)"
pause

# ── Step 3: Default scheduler — Scenario 4 ───────────────────────────────────
banner "STEP 3/6 — Deploy Scenario 4 with the DEFAULT scheduler"
echo "Applying scenario4-default.yaml (3 nginx + 3 stress-ng pods)."
echo ""
kubectl apply -f workloads/scenarios/scenario4-default.yaml --context "${CONTEXT}"
echo ""
echo "Waiting for pods to be Running..."
kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
  -l energy.project/scenario=scenario4 \
  -n default --context "${CONTEXT}" --timeout=120s
echo ""
echo -e "${GREEN}Pod placement — default-scheduler:${RESET}"
kubectl get pods -n default --context "${CONTEXT}" -o wide \
  --selector energy.project/scenario=scenario4
pause

# ── Step 4: Energy-aware scheduler — Scenario 4 ──────────────────────────────
banner "STEP 4/6 — Deploy Scenario 4 with the ENERGY-AWARE scheduler"
echo "Cleaning up default-scheduler pods first..."
kubectl delete -f workloads/scenarios/scenario4-default.yaml \
  --context "${CONTEXT}" --timeout=60s 2>/dev/null || true
# Wait until clear
sleep 5

echo ""
echo "Applying scenario4-energy-aware.yaml..."
kubectl apply -f workloads/scenarios/scenario4-energy-aware.yaml --context "${CONTEXT}"
echo ""
echo "Waiting for pods to be Running..."
kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
  -l energy.project/scenario=scenario4 \
  -n default --context "${CONTEXT}" --timeout=120s
echo ""
echo -e "${GREEN}Pod placement — energy-aware-scheduler:${RESET}"
kubectl get pods -n default --context "${CONTEXT}" -o wide \
  --selector energy.project/scenario=scenario4
pause

# ── Step 5: Scoring log lines ─────────────────────────────────────────────────
banner "STEP 5/6 — Plugin scoring log: R_i, L_i, P_i per node"
echo "Showing the last EnergyAware scored-node log lines."
echo "Each line shows how the plugin scored each candidate node."
echo ""
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=energy-aware-scheduler \
  --context "${CONTEXT}" \
  --tail=60 2>/dev/null \
  | grep -i "EnergyAware scored" | tail -15 || \
  echo "(No recent scoring log lines found — try deploying a pod first.)"
pause

# ── Step 6: Charts ────────────────────────────────────────────────────────────
banner "STEP 6/6 — Results charts"
echo "Charts from results/week6/charts/ (open in file manager or IDE):"
echo ""
ls -1 "${BASE_DIR}/results/week6/charts/" 2>/dev/null || \
  echo "(Charts not yet generated — run python3 scripts/analyze_results.py)"
echo ""
echo "Key charts to show:"
echo "  power_by_scenario.png      — power comparison with error bars"
echo "  p95_latency_scenario4.png  — p95 HTTP latency (Scenario 4)"
echo "  weight_sensitivity.png     — power vs latency trade-off (tuning)"
pause

# ── Cleanup ───────────────────────────────────────────────────────────────────
banner "Demo complete — cleanup"
echo "Removing Scenario 4 workloads..."
kubectl delete -f workloads/scenarios/scenario4-energy-aware.yaml \
  --context "${CONTEXT}" --ignore-not-found=true --timeout=60s 2>/dev/null || true
echo ""
echo -e "${GREEN}✓ Demo complete.${RESET}"
echo ""
echo "If anything failed, see docs/demo-fallback.md for the backup plan."
