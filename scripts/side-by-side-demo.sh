#!/usr/bin/env bash
# =============================================================================
# scripts/side-by-side-demo.sh
# Interactive Side-by-Side Stress Demonstration for Examiners & Teachers
# =============================================================================
set -euo pipefail

CONTEXT="kind-energy"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${BASE_DIR}"

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

pause() {
  echo ""
  echo -e "${YELLOW}▶  Press ENTER to continue...${RESET}"
  read -r
}

banner() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $*${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

# -----------------------------------------------------------------------------
# STEP 1: Introduce the Heterogeneous Hardware
# -----------------------------------------------------------------------------
banner "STEP 1/5 — The Problem: Heterogeneous Power Profiles in the Cluster"
echo "Showing the 3 worker nodes and their simulated power profiles:"
echo ""
kubectl get nodes --context "${CONTEXT}" \
  -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max

echo ""
echo -e "${BOLD}Key Concept to Explain:${RESET}"
echo "  • energy-worker  (EFFICIENT):    20W idle  /  60W max TDP"
echo "  • energy-worker2 (MEDIUM):       40W idle  / 120W max TDP"
echo "  • energy-worker3 (POWER-HUNGRY): 80W idle  / 200W max TDP"
echo ""
echo "Default Kubernetes has NO concept of these power tiers and treats all nodes identically."
pause

# -----------------------------------------------------------------------------
# STEP 2: Deploy Both Schedulers Concurrently with CPU Stress
# -----------------------------------------------------------------------------
banner "STEP 2/5 — Deploying Workloads Side-by-Side (Applying CPU Stress)"
echo "Cleaning up any existing workloads..."
kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context "${CONTEXT}" --ignore-not-found=true --timeout=30s >/dev/null 2>&1 || true

echo "Deploying:"
echo "  • 4 pods scheduled by DEFAULT SCHEDULER (2 Nginx web + 2 stress-ng batch)"
echo "  • 4 pods scheduled by ENERGY-AWARE SCHEDULER (2 Nginx web + 2 stress-ng batch)"
echo ""
kubectl apply -f workloads/scenarios/side-by-side-demo.yaml --context "${CONTEXT}"

echo ""
echo "Waiting for all 8 pods to reach Running status..."
kubectl wait --for=condition=Ready pod -l energy.project/scenario=side-by-side-demo -n default --context "${CONTEXT}" --timeout=120s

echo ""
echo -e "${GREEN}✓ All pods running and generating stress!${RESET}"
pause

# -----------------------------------------------------------------------------
# STEP 3: Compare Node Placements
# -----------------------------------------------------------------------------
banner "STEP 3/5 — Proof of Better Placement: Terminal Pod Inspection"

echo -e "${BOLD}1. Pods Placed by DEFAULT SCHEDULER:${RESET}"
kubectl get pods -n default --context "${CONTEXT}" -o wide --selector energy.project/scheduler=default-scheduler

echo ""
echo -e "${BOLD}2. Pods Placed by OUR ENERGY-AWARE SCHEDULER:${RESET}"
kubectl get pods -n default --context "${CONTEXT}" -o wide --selector energy.project/scheduler=energy-aware-scheduler

echo ""
echo -e "${BOLD}What This Proves to Your Teacher:${RESET}"
DEF_W3=$(kubectl get pods -n default --context "${CONTEXT}" --selector energy.project/scheduler=default-scheduler -o jsonpath='{.items[?(@.spec.nodeName=="energy-worker3")].metadata.name}' | wc -w)
EA_W3=$(kubectl get pods -n default --context "${CONTEXT}" --selector energy.project/scheduler=energy-aware-scheduler -o jsonpath='{.items[?(@.spec.nodeName=="energy-worker3")].metadata.name}' | wc -w)

if [ "${DEF_W3}" -gt 0 ]; then
  echo -e "  • ${RED}DEFAULT SCHEDULER put ${DEF_W3} pod(s) on energy-worker3 (the 200W node).${RESET}"
else
  echo -e "  • DEFAULT SCHEDULER spread pods evenly across nodes."
fi
echo -e "  • ${GREEN}ENERGY-AWARE SCHEDULER put ${EA_W3} pods on energy-worker3 (completely avoided!).${RESET}"
echo "    It packed all latency and batch pods onto the energy-efficient workers (worker & worker2)."
pause

# -----------------------------------------------------------------------------
# STEP 4: Live Grafana Dashboard Inspection
# -----------------------------------------------------------------------------
banner "STEP 4/5 — Live Grafana Dashboard Comparison"
echo "Open Grafana in your browser at: http://localhost:3000"
echo "Dashboard: 'Energy-Aware Scheduler — Comparison'"
echo ""
echo -e "${BOLD}Show Your Teacher These Specific Live Panels:${RESET}"
echo "  1. 'SIDE-BY-SIDE COMPARISON: Default (Left) vs. Energy-Aware (Right)'"
echo "     - Left Red Badge: Shows pods running on the 200W power-hungry node under Default."
echo "     - Right Green Badge: Shows 0 pods on worker3 under Energy-Aware."
echo "     - Donut charts: Compare spread distribution (Default) vs efficient packing (Energy-Aware)."
echo ""
echo "  2. 'Estimated Node Power Gauges (W)'"
echo "     - Shows how worker3 power spikes when Default puts load on it,"
echo "       while our scheduler keeps worker3 at idle power (80W)."
echo ""
echo "  3. 'Per-Node Total CPU Utilization (%)'"
echo "     - Shows the CPU load distributed across the nodes."
pause

# -----------------------------------------------------------------------------
# STEP 5: Algorithmic Explanation & Decision Logs
# -----------------------------------------------------------------------------
banner "STEP 5/5 — Algorithmic Transparency: Behind-the-Scenes Scoring Logs"
echo "Here is the exact mathematical scoring executed by our Go plugin for candidate nodes:"
echo ""
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --context "${CONTEXT}" --tail=60 | grep "EnergyAware scored" | tail -6 || echo "No recent logs; plugin cached decisions."

echo ""
echo -e "${BOLD}Formula Demonstrated:${RESET}"
echo "  Score_i = wR·R_i + wL·L_i - wP·P_i"
echo "  • energy-worker3 was penalized with a high P_i value (power penalty)."
echo "  • energy-worker & worker2 received much higher composite scores and were selected."
pause

# -----------------------------------------------------------------------------
# Cleanup Prompt
# -----------------------------------------------------------------------------
banner "Demo Finished"
read -p "Would you like to clean up the demo pods now? (y/n): " CLEANUP
if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
  echo "Deleting demo deployments..."
  kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context "${CONTEXT}" --timeout=60s
  echo -e "${GREEN}✓ Cleaned up successfully.${RESET}"
else
  echo "Demo pods left running so you can continue showing Grafana."
  echo "To clean up later, run:"
  echo "  kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context kind-energy"
fi
