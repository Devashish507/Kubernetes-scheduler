#!/usr/bin/env python3
"""
scripts/tune_weights.py
Week 6 – Weight Grid Search (Task 3)

Grid-searches (wR, wL, wP) combinations for the two workload-type profiles
(latency-sensitive and batch).  For each combination it:

  1. Patches the scheduler ConfigMap with the new weights.
  2. Restarts the energy-aware-scheduler Deployment and waits until Ready.
  3. Runs Scenario 4 once via a single run-experiments-like loop.
  4. Records total estimated cluster power, p95 latency (from fortio), and
     utilisation spread.

All combinations are saved to results/week6/tuning.csv.  After the search, the
best combination is selected using a clearly documented rule and printed.

Selection rule (see docs/week6-notes.md for rationale):
  "Among all combinations whose p95 latency is within 10% of the lowest
   observed p95 latency across all combinations, select the one with the
   lowest total estimated cluster power."
  This prioritises power savings while protecting latency quality.

NOTE: Grid values are chosen so each profile has < 15 combinations.
      All weights must be positive and sum to 1.0 (within floating-point
      tolerance) — this mirrors the constraint in the plugin design.

Usage:
  python3 scripts/tune_weights.py

Prerequisites:
  - Kind cluster "energy" is running.
  - energy-aware-scheduler Deployment exists in kube-system.
  - workloads/load-generator.yaml is available.
  - Prometheus is reachable via port-forward on :9098.
  - fortio/fortio image has been pulled into the cluster nodes.

Do NOT add unit tests.
"""

import csv
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
RESULTS_DIR = BASE_DIR / "results" / "week6"
TUNING_CSV = RESULTS_DIR / "tuning.csv"
SCENARIO_MANIFEST = BASE_DIR / "workloads" / "scenarios" / "scenario4-energy-aware.yaml"
LOAD_GEN_MANIFEST = BASE_DIR / "workloads" / "load-generator.yaml"
CONFIGMAP_MANIFEST = BASE_DIR / "scheduler" / "manifests" / "configmap.yaml"
CONTEXT = "kind-energy"

# Power model (must match label-nodes.sh)
POWER_PROFILES = {
    "energy-worker":  {"p_idle": 20.0, "p_max": 60.0},
    "energy-worker2": {"p_idle": 40.0, "p_max": 120.0},
    "energy-worker3": {"p_idle": 80.0, "p_max": 200.0},
}

# ---------------------------------------------------------------------------
# Weight grid – each value is in {0.2, 0.4, 0.6}.
# Only triples (wR, wL, wP) that sum to 1.0 are kept.
# This yields exactly 6 valid triples per profile — well under the 15 cap.
# ---------------------------------------------------------------------------
GRID_VALUES = [0.2, 0.4, 0.6]


def generate_grid():
    """Return all (wR, wL, wP) triples from GRID_VALUES that sum to 1.0."""
    combos = []
    for wR in GRID_VALUES:
        for wL in GRID_VALUES:
            for wP in GRID_VALUES:
                if abs(wR + wL + wP - 1.0) < 1e-9:
                    combos.append((round(wR, 1), round(wL, 1), round(wP, 1)))
    return combos


# ---------------------------------------------------------------------------
# Kubernetes helpers
# ---------------------------------------------------------------------------

def run_cmd(args, check=True, capture=False, timeout=120):
    """Run a shell command.  Returns CompletedProcess."""
    kwargs = dict(check=check, timeout=timeout)
    if capture:
        kwargs["capture_output"] = True
        kwargs["text"] = True
    return subprocess.run(args, **kwargs)


def patch_configmap(lat_wr, lat_wl, lat_wp, bat_wr, bat_wl, bat_wp):
    """
    Patch the energy-aware-scheduler ConfigMap in-place using kubectl patch.
    The ConfigMap stores a KubeSchedulerConfiguration YAML string under the
    key 'scheduler-config.yaml'.  We re-render the entire data block.
    """
    config_yaml = f"""\
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration

leaderElection:
  leaderElect: true
  resourceName: energy-aware-scheduler
  resourceNamespace: kube-system

profiles:
  - schedulerName: energy-aware-scheduler
    plugins:
      score:
        enabled:
          - name: EnergyAware
    pluginConfig:
      - name: EnergyAware
        args:
          utilizationThreshold: 80
          maxReferencePowerW: 200
          prometheusURL: ""
          latencySensitiveWeights:
            wR: {lat_wr}
            wL: {lat_wl}
            wP: {lat_wp}
          batchWeights:
            wR: {bat_wr}
            wL: {bat_wl}
            wP: {bat_wp}
"""
    # Use kubectl create/apply via a patch that replaces the data value.
    patch_json = json.dumps({
        "data": {
            "scheduler-config.yaml": config_yaml
        }
    })
    run_cmd([
        "kubectl", "patch", "configmap", "energy-aware-scheduler-config",
        "-n", "kube-system",
        "--context", CONTEXT,
        "--type=merge",
        "-p", patch_json,
    ])
    print(f"    [tune] ConfigMap patched: lat=({lat_wr},{lat_wl},{lat_wp}) "
          f"bat=({bat_wr},{bat_wl},{bat_wp})")


def restart_scheduler_and_wait(timeout_s=120):
    """Restart the scheduler Deployment and wait until all replicas are Ready."""
    run_cmd([
        "kubectl", "rollout", "restart",
        "deployment/energy-aware-scheduler",
        "-n", "kube-system",
        "--context", CONTEXT,
    ])
    print("    [tune] Scheduler restart triggered; waiting for rollout…")
    run_cmd([
        "kubectl", "rollout", "status",
        "deployment/energy-aware-scheduler",
        "-n", "kube-system",
        "--context", CONTEXT,
        f"--timeout={timeout_s}s",
    ], timeout=timeout_s + 10)
    print("    [tune] Scheduler rollout complete.")
    time.sleep(5)   # Give the new pod a moment to initialise its Prometheus cache.


def cleanup_namespace():
    """Delete all workloads from the default namespace and wait until clean."""
    run_cmd([
        "kubectl", "delete", "deployments,pods,jobs",
        "--all", "-n", "default",
        "--context", CONTEXT,
        "--ignore-not-found=true",
        "--timeout=90s",
    ], check=False, timeout=100)
    # Poll until empty.
    for _ in range(45):
        result = run_cmd(
            ["kubectl", "get", "pods", "-n", "default",
             "--context", CONTEXT, "--no-headers"],
            check=False, capture=True, timeout=15
        )
        lines = [l for l in result.stdout.splitlines() if l.strip()]
        if not lines:
            break
        time.sleep(2)
    time.sleep(3)


def apply_manifest(path):
    run_cmd(["kubectl", "apply", "-f", str(path), "--context", CONTEXT])


def wait_pods_running(scenario_label, timeout_s=120):
    """Wait until all pods with the given scenario label are Running."""
    result = run_cmd([
        "kubectl", "wait",
        f"--for=jsonpath={{.status.phase}}=Running",
        "pod",
        f"-l", f"energy.project/scenario={scenario_label}",
        "-n", "default",
        "--context", CONTEXT,
        f"--timeout={timeout_s}s",
    ], check=False, timeout=timeout_s + 10)
    return result.returncode == 0


def query_prometheus_utilisation():
    """
    Start a port-forward to Prometheus on :9098, query CPU utilisation per
    node, kill the port-forward, and return a dict {nodename: util_pct}.
    Returns empty dict on failure.
    """
    pf_port = 9098
    pf = subprocess.Popen([
        "kubectl", "port-forward", "-n", "monitoring",
        f"svc/kube-prometheus-stack-prometheus",
        f"{pf_port}:9090",
        "--context", CONTEXT,
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(4)

    promql = (
        '100 - (avg by (instance) '
        '(rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) '
        '* on(instance) group_left(nodename) node_uname_info'
    )
    util = {}
    try:
        import urllib.request
        import urllib.parse
        url = f"http://localhost:{pf_port}/api/v1/query?" + urllib.parse.urlencode({"query": promql})
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
        for res in data.get("data", {}).get("result", []):
            nodename = res.get("metric", {}).get("nodename") or res.get("metric", {}).get("node")
            if nodename:
                val = float(res["value"][1])
                util[nodename] = max(0.0, min(100.0, val))
    except Exception as e:
        print(f"    [tune] WARNING: Prometheus query failed: {e}")
    finally:
        pf.terminate()

    return util


def compute_total_power(util_dict):
    """Compute total estimated cluster power in Watts from utilisation dict."""
    total = 0.0
    for node, prof in POWER_PROFILES.items():
        u = util_dict.get(node, 0.0) / 100.0
        total += prof["p_idle"] + (prof["p_max"] - prof["p_idle"]) * u
    return total


def compute_util_spread(util_dict):
    """Return max - min utilisation across worker nodes (pct points)."""
    vals = [util_dict.get(n, 0.0) for n in POWER_PROFILES]
    return max(vals) - min(vals)


def run_fortio_job_and_get_p95():
    """
    Apply the load-generator.yaml (Service + Job), wait for Job completion,
    parse the fortio stdout for the p95 latency, clean up the Job, and
    return p95 in milliseconds.  Returns None if the Job fails or if the
    latency cannot be parsed.

    The fortio text output contains lines like:
        50.00 % <= 5.3 ms
        75.00 % <= 8.1 ms
        90.00 % <= 12.4 ms
        95.00 % <= 18.9 ms
        99.00 % <= 45.2 ms
        99.90 % <= 80.1 ms
    We look for the line with '95.00 %'.
    """
    apply_manifest(LOAD_GEN_MANIFEST)
    print("    [tune] fortio Job applied; waiting for completion…")

    completed = run_cmd([
        "kubectl", "wait",
        "--for=condition=complete",
        "job/fortio-load-test",
        "-n", "default",
        "--context", CONTEXT,
        "--timeout=150s",
    ], check=False, timeout=160)

    if completed.returncode != 0:
        print("    [tune] WARNING: fortio Job did not complete.")
        _delete_fortio_job()
        return None

    # Capture logs.
    log_result = run_cmd([
        "kubectl", "logs",
        "-n", "default",
        "-l", "job-name=fortio-load-test",
        "--context", CONTEXT,
    ], check=False, capture=True, timeout=30)

    p95_ms = _parse_fortio_p95(log_result.stdout)
    _delete_fortio_job()
    return p95_ms


def _delete_fortio_job():
    run_cmd([
        "kubectl", "delete", "job", "fortio-load-test",
        "-n", "default",
        "--context", CONTEXT,
        "--ignore-not-found=true",
    ], check=False, timeout=30)


def _parse_fortio_p95(text):
    """
    Parse p95 latency in milliseconds from fortio text output.
    Fortio prints percentile lines in the format:
        XX.XX % <= YY.YY ms
    or (for sub-millisecond values):
        XX.XX % <= 0.YYY ms

    Returns float ms, or None if not found.
    """
    import re
    # Match lines like "95.00 % <= 18.9 ms" or "95.00% <= 18.9 ms"
    pattern = re.compile(
        r'95\.00\s*%\s*<=\s*([0-9]+(?:\.[0-9]+)?)\s*(ms|µs|s|us)',
        re.IGNORECASE
    )
    for line in text.splitlines():
        m = pattern.search(line)
        if m:
            val = float(m.group(1))
            unit = m.group(2).lower()
            if unit in ("µs", "us"):
                val /= 1000.0   # µs → ms
            elif unit == "s":
                val *= 1000.0   # s → ms
            return round(val, 3)
    return None


# ---------------------------------------------------------------------------
# Main grid-search loop
# ---------------------------------------------------------------------------

def main():
    grid = generate_grid()
    print(f"\n[tune] Weight grid has {len(grid)} combinations per profile.")
    print("[tune] Each combination uses the same (wR, wL, wP) for BOTH profiles")
    print("[tune]   latency-sensitive: high wL emphasis per combo")
    print("[tune]   batch: same combo — wP signal comes from node power labels\n")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "combo_id",
        "lat_wR", "lat_wL", "lat_wP",
        "bat_wR", "bat_wL", "bat_wP",
        "total_power_W",
        "p95_latency_ms",
        "util_spread_pct",
        "pods_ready",
        "status",
    ]

    rows = []

    for idx, (wR, wL, wP) in enumerate(grid, start=1):
        combo_id = f"combo{idx:02d}"
        print(f"\n{'='*60}")
        print(f"[tune] Combo {idx}/{len(grid)}: wR={wR} wL={wL} wP={wP}")
        print(f"{'='*60}")

        # For the latency-sensitive profile we use exactly (wR, wL, wP) —
        # wL is already embedded in the grid direction.
        # For batch we swap wL ↔ wP to make power more dominant
        # ONLY when the combo has wL > wP (i.e. not already power-focused).
        # This gives meaningful differentiation between profiles.
        lat_wR, lat_wL, lat_wP = wR, wL, wP
        if wL > wP:
            bat_wR, bat_wL, bat_wP = wR, wP, wL   # swap for batch
        else:
            bat_wR, bat_wL, bat_wP = wR, wL, wP   # already power-focused

        row = {
            "combo_id": combo_id,
            "lat_wR": lat_wR, "lat_wL": lat_wL, "lat_wP": lat_wP,
            "bat_wR": bat_wR, "bat_wL": bat_wL, "bat_wP": bat_wP,
            "total_power_W": None,
            "p95_latency_ms": None,
            "util_spread_pct": None,
            "pods_ready": False,
            "status": "failed",
        }

        try:
            # 1. Patch ConfigMap.
            patch_configmap(lat_wR, lat_wL, lat_wP, bat_wR, bat_wL, bat_wP)

            # 2. Restart scheduler and wait.
            restart_scheduler_and_wait()

            # 3. Clean up namespace.
            cleanup_namespace()

            # 4. Apply Scenario 4 (energy-aware).
            apply_manifest(SCENARIO_MANIFEST)

            # 5. Wait for ALL pods (latency + batch) to be Running.
            pods_ready = wait_pods_running("scenario4", timeout_s=120)
            row["pods_ready"] = pods_ready

            if not pods_ready:
                print(f"    [tune] Pods not ready — skipping metrics for {combo_id}.")
                row["status"] = "pods_not_ready"
                rows.append(row)
                cleanup_namespace()
                continue

            print("    [tune] All pods Running. Waiting 15s for metric stabilisation…")
            time.sleep(15)

            # 6. Run fortio load test (batch pods are still running).
            p95_ms = run_fortio_job_and_get_p95()
            row["p95_latency_ms"] = p95_ms

            # 7. Query Prometheus utilisation and compute power.
            util = query_prometheus_utilisation()
            total_power = compute_total_power(util)
            spread = compute_util_spread(util)
            row["total_power_W"] = round(total_power, 2)
            row["util_spread_pct"] = round(spread, 2)
            row["status"] = "ok" if p95_ms is not None else "latency_parse_failed"

            print(f"    [tune] Power={total_power:.2f}W  "
                  f"p95={p95_ms}ms  spread={spread:.2f}pct")

        except Exception as exc:
            print(f"    [tune] ERROR in {combo_id}: {exc}")
            row["status"] = f"error:{exc}"

        finally:
            cleanup_namespace()

        rows.append(row)

    # ── Write tuning.csv ──────────────────────────────────────────────────────
    with open(TUNING_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"\n[tune] Saved {len(rows)} rows to {TUNING_CSV}")

    # ── Select best combination ───────────────────────────────────────────────
    _select_best(rows)


def _select_best(rows):
    """
    Selection rule (documented in docs/week6-notes.md):

      Step 1: Collect all combinations where status == 'ok' and
              p95_latency_ms is not None.
      Step 2: Find the minimum p95 latency across those combinations
              (p95_min).
      Step 3: Keep only combinations with p95_latency_ms <= p95_min * 1.10
              (within 10% of the best latency).
      Step 4: Among those, select the combination with the lowest
              total_power_W.

    This rule prioritises power savings while protecting latency quality:
    we accept a slightly non-minimum-power combination as long as it keeps
    latency close to optimal.  The 10% tolerance is conventional for
    SLA headroom in resource management literature.
    """
    print("\n" + "="*60)
    print("[tune] SELECTION RULE:")
    print("  Among all OK combinations with p95 latency within 10%")
    print("  of the best observed p95, choose the lowest power.")
    print("="*60)

    ok_rows = [r for r in rows
               if r["status"] == "ok"
               and r["p95_latency_ms"] is not None
               and r["total_power_W"] is not None]

    if not ok_rows:
        print("[tune] No successful combinations found. Cannot select best.")
        return

    p95_min = min(r["p95_latency_ms"] for r in ok_rows)
    threshold = p95_min * 1.10
    candidates = [r for r in ok_rows if r["p95_latency_ms"] <= threshold]

    if not candidates:
        candidates = ok_rows   # fallback: all ok rows

    best = min(candidates, key=lambda r: r["total_power_W"])

    print(f"\n  Minimum p95 across all OK combos : {p95_min:.3f} ms")
    print(f"  10% tolerance threshold          : {threshold:.3f} ms")
    print(f"  Candidates within threshold      : {len(candidates)}")
    print(f"\n  ★ BEST COMBINATION: {best['combo_id']}")
    print(f"    latency-sensitive : wR={best['lat_wR']} wL={best['lat_wL']} wP={best['lat_wP']}")
    print(f"    batch             : wR={best['bat_wR']} wL={best['bat_wL']} wP={best['bat_wP']}")
    print(f"    Total power       : {best['total_power_W']} W")
    print(f"    p95 latency       : {best['p95_latency_ms']} ms")
    print(f"    Utilisation spread: {best['util_spread_pct']} pct-pts")
    print()
    print("  Update scheduler/manifests/configmap.yaml with these weights.")
    print("  Record old and new values in docs/scoring-model.md.")


if __name__ == "__main__":
    main()
