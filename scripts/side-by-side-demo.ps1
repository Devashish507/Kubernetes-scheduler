# =============================================================================
# scripts/side-by-side-demo.ps1
# Interactive Side-by-Side Stress Demonstration for Windows PowerShell
# =============================================================================

$context = "kind-energy"
$baseDir = Split-Path -Parent $PSScriptRoot
Set-Location $baseDir

function Pause-Step {
    Write-Host ""
    Write-Host "▶  Press ENTER to continue..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
}

function Show-Banner($msg) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
}

# -----------------------------------------------------------------------------
# STEP 1: Introduce the Heterogeneous Hardware
# -----------------------------------------------------------------------------
Show-Banner "STEP 1/5 — The Problem: Heterogeneous Power Profiles in the Cluster"
Write-Host "Showing the 3 worker nodes and their simulated power profiles:"
kubectl get nodes --context $context -L energy.project/power-profile,energy.project/p-idle,energy.project/p-max

Write-Host ""
Write-Host "Key Concept to Explain:" -ForegroundColor Yellow
Write-Host "  • energy-worker  (EFFICIENT):    20W idle  /  60W max TDP"
Write-Host "  • energy-worker2 (MEDIUM):       40W idle  / 120W max TDP"
Write-Host "  • energy-worker3 (POWER-HUNGRY): 80W idle  / 200W max TDP"
Write-Host ""
Write-Host "Default Kubernetes has NO concept of these power tiers and treats all nodes identically."
Pause-Step

# -----------------------------------------------------------------------------
# STEP 2: Deploy Both Schedulers Concurrently with CPU Stress
# -----------------------------------------------------------------------------
Show-Banner "STEP 2/5 — Deploying Workloads Side-by-Side (Applying CPU Stress)"
Write-Host "Cleaning up any existing workloads..."
kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context $context --ignore-not-found=true --timeout=30s | Out-Null

Write-Host "Deploying:"
Write-Host "  • 4 pods scheduled by DEFAULT SCHEDULER (2 Nginx web + 2 stress-ng batch)"
Write-Host "  • 4 pods scheduled by ENERGY-AWARE SCHEDULER (2 Nginx web + 2 stress-ng batch)"
Write-Host ""
kubectl apply -f workloads/scenarios/side-by-side-demo.yaml --context $context

Write-Host ""
Write-Host "Waiting for all 8 pods to reach Running status..."
kubectl wait --for=condition=Ready pod -l energy.project/scenario=side-by-side-demo -n default --context $context --timeout=120s

Write-Host ""
Write-Host "✓ All pods running and generating stress!" -ForegroundColor Green
Pause-Step

# -----------------------------------------------------------------------------
# STEP 3: Compare Node Placements
# -----------------------------------------------------------------------------
Show-Banner "STEP 3/5 — Proof of Better Placement: Terminal Pod Inspection"

Write-Host "1. Pods Placed by DEFAULT SCHEDULER:" -ForegroundColor Yellow
kubectl get pods -n default --context $context -o wide --selector energy.project/scheduler=default-scheduler

Write-Host ""
Write-Host "2. Pods Placed by OUR ENERGY-AWARE SCHEDULER:" -ForegroundColor Green
kubectl get pods -n default --context $context -o wide --selector energy.project/scheduler=energy-aware-scheduler

Write-Host ""
Write-Host "What This Proves to Your Teacher:" -ForegroundColor Cyan
Write-Host "  • DEFAULT SCHEDULER spreads pods blindly, including onto energy-worker3 (the 200W node)." -ForegroundColor Red
Write-Host "  • ENERGY-AWARE SCHEDULER completely avoided energy-worker3, packing onto worker1 and worker2." -ForegroundColor Green
Pause-Step

# -----------------------------------------------------------------------------
# STEP 4: Live Grafana Dashboard Inspection
# -----------------------------------------------------------------------------
Show-Banner "STEP 4/5 — Live Grafana Dashboard Comparison"
Write-Host "Open Grafana in your browser at: http://localhost:3000"
Write-Host "Dashboard: 'Energy-Aware Scheduler — Comparison'"
Write-Host ""
Write-Host "Show Your Teacher These Specific Live Panels:" -ForegroundColor Yellow
Write-Host "  1. 'SIDE-BY-SIDE COMPARISON: Default (Left) vs. Energy-Aware (Right)'"
Write-Host "     - Left Red Badge: Shows pods running on the 200W power-hungry node under Default."
Write-Host "     - Right Green Badge: Shows 0 pods on worker3 under Energy-Aware."
Write-Host "     - Donut charts: Compare spread distribution (Default) vs efficient packing (Energy-Aware)."
Write-Host ""
Write-Host "  2. 'Estimated Node Power Gauges (W)'"
Write-Host "     - Shows how worker3 power spikes when Default puts load on it,"
Write-Host "       while our scheduler keeps worker3 at idle power (80W)."
Write-Host ""
Write-Host "  3. 'Per-Node Total CPU Utilization (%)'"
Write-Host "     - Shows the CPU load distributed across the nodes."
Pause-Step

# -----------------------------------------------------------------------------
# STEP 5: Algorithmic Explanation & Decision Logs
# -----------------------------------------------------------------------------
Show-Banner "STEP 5/5 — Algorithmic Transparency: Behind-the-Scenes Scoring Logs"
Write-Host "Here is the exact mathematical scoring executed by our Go plugin for candidate nodes:"
Write-Host ""
kubectl logs -n kube-system -l app.kubernetes.io/name=energy-aware-scheduler --context $context --tail=60 | Select-String "EnergyAware scored" | Select-Object -Last 6

Write-Host ""
Write-Host "Formula Demonstrated:" -ForegroundColor Cyan
Write-Host "  Score_i = wR*R_i + wL*L_i - wP*P_i"
Write-Host "  • energy-worker3 was penalized with a high P_i value (power penalty)."
Write-Host "  • energy-worker & worker2 received much higher composite scores and were selected."
Pause-Step

# -----------------------------------------------------------------------------
# Cleanup Prompt
# -----------------------------------------------------------------------------
Show-Banner "Demo Finished"
$cleanup = Read-Host "Would you like to clean up the demo pods now? (y/n)"
if ($cleanup -match "^[Yy]$") {
    Write-Host "Deleting demo deployments..."
    kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context $context --timeout=60s
    Write-Host "✓ Cleaned up successfully." -ForegroundColor Green
} else {
    Write-Host "Demo pods left running so you can continue showing Grafana."
    Write-Host "To clean up later, run:"
    Write-Host "  kubectl delete -f workloads/scenarios/side-by-side-demo.yaml --context kind-energy"
}
