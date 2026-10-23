# Week 7 Checklist

> **B.Tech Final-Year Project — Energy-Aware Kubernetes Scheduler**  
> Run each section after completing the corresponding task.
> Record pass/fail and any deviations.

---

## 0. Pre-flight: Fresh Clone Test

This is the top-level reproducibility check. Run it on a machine that has
never had this project before (or after `bash scripts/teardown.sh`).

```bash
# 0a. Clone into a fresh directory
git clone <repo-url> schedular-fresh-clone
cd schedular-fresh-clone

# 0b. Install Python deps
pip install -r scripts/requirements.txt

# 0c. Run the full pipeline
bash scripts/run-all.sh
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| `bash scripts/run-all.sh` exits 0 | All 10 steps complete without error |
| OR: exact failure step is documented here | Document the step name and error message |

**Result:** _(fill in after test)_

---

## Task 1 — Final Analysis (`docs/final-analysis.md`)

```bash
# 1a. Confirm deltas.csv exists
python3 scripts/compute_deltas.py
ls -lh results/week7/deltas.csv

# 1b. Confirm row count (expect 1 header + 16 data rows = 17 lines)
#     4 scenarios × 4 metrics = 16; p95 only appears for scenario4
wc -l results/week7/deltas.csv

# 1c. Confirm no [RUN] placeholders remain in final-analysis.md
#     (after you fill in the numbers from the CSVs)
grep -c "\[CSV\]" docs/final-analysis.md
# Expected after fill-in: 0
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| `deltas.csv` exists | File present after `compute_deltas.py` |
| Every `[CSV]` tag replaced | `grep -c "\[CSV\]" docs/final-analysis.md` → 0 |
| delta_pct computable | No `N/A` in `delta_pct` column for power/delay/spread rows |
| "Where it did not help" section present | `grep -i "where it did not help" docs/final-analysis.md` → 1 match |
| "Threats to validity" section present | `grep -i "threats to validity" docs/final-analysis.md` → 1 match |
| All explanations labelled as hypotheses | No claim of "finding" without data |

---

## Task 2 — Trimaran Baseline

```bash
# 2a. Confirm trimaran-attempt.md exists and is non-trivial
ls -lh docs/trimaran-attempt.md
wc -l docs/trimaran-attempt.md
# Expected: > 30 lines (substantive documentation)
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| `docs/trimaran-attempt.md` exists | File present |
| Documents prerequisites from actual repo README | Contains "load-watcher" and config key names |
| States why it was not deployed | Clear explanation of time budget / image concerns |

---

## Task 3 — Reproducibility

### 3a. README commands

```bash
# Every command in README.md must exist as a script or kubectl command.
# Check each command reference:
grep "bash scripts/" README.md | sed 's/.*bash //' | awk '{print $1}' | sort -u | while read script; do
  [ -f "${script}" ] && echo "OK: ${script}" || echo "MISSING: ${script}"
done
```

Expected: All scripts listed in README.md are present in `scripts/`.

### 3b. run-all.sh

```bash
# Run with --skip-setup if cluster is already running
bash scripts/run-all.sh --skip-setup
# Expected exit code: 0
echo "Exit code: $?"
```

### 3c. environment.md

```bash
ls -lh docs/environment.md
grep "PASTE OUTPUT" docs/environment.md | wc -l
# Expected: 4 paste-here prompts (kubectl, kind, helm, go versions)
# After filling in: 0
```

### 3d. requirements.txt

```bash
pip install -r scripts/requirements.txt
python3 -c "import matplotlib, numpy; print('OK')"
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| All README scripts present | No "MISSING:" output from check above |
| `run-all.sh` exits 0 | Full pipeline completes |
| `environment.md` has version slots | File present with kubectl/kind/helm/go sections |
| `requirements.txt` installs cleanly | `pip install -r` exits 0 |
| Helm chart version pinned | `grep "CHART_VERSION" scripts/install-monitoring.sh` shows `91.5.2` |

---

## Task 4 — Repo Cleanup

```bash
# 4a. No secrets or kubeconfigs committed
git ls-files | grep -i "kubeconfig\|.kube\|password\|secret" || echo "OK: no secret files"

# 4b. .gitignore exists
ls .gitignore

# 4c. Original LICENSE preserved in forked directory
ls scheduler/scheduler-plugins/LICENSE

# 4d. Attribution document exists
ls docs/contribution.md
grep -i "pkg/energyaware" docs/contribution.md | wc -l
# Expected: >= 4 mentions (original work section)

# 4e. No large binary blobs
git ls-files -z | xargs -0 wc -c 2>/dev/null | sort -rn | head -10
# No file should be > 5 MB (results CSVs and PNGs are typically < 1 MB)
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| No secrets committed | `git ls-files | grep -i "password"` → empty |
| `.gitignore` present | File exists |
| LICENSE preserved | `scheduler/scheduler-plugins/LICENSE` exists |
| `contribution.md` present | File exists with attribution for PEAKS, Kepler, scheduler-plugins |
| No files > 5 MB | `git ls-files` shows no unexpected large files |

---

## Task 5 — Paper Material

```bash
# 5a. All four paper docs exist
ls docs/paper-implementation-section.md \
   docs/paper-results-section.md \
   docs/paper-edits.md \
   docs/paper-figures.md

# 5b. Results section references only files in results/week6/charts/
grep "results/" docs/paper-results-section.md | grep -v "week6/charts\|week6/summary\|week7/deltas"
# Expected: empty (all references are to the correct result files)

# 5c. paper-edits.md contains sentence replacements
grep -c "Suggested replacement" docs/paper-edits.md
# Expected: >= 5

# 5d. paper-figures.md lists all 5 chart files
for chart in power_by_scenario latency_by_scenario utilization_scenario4 p95_latency_scenario4 weight_sensitivity; do
  grep -l "${chart}" docs/paper-figures.md > /dev/null && echo "OK: ${chart}" || echo "MISSING: ${chart}"
done
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| All 4 paper docs present | `ls` succeeds for all four |
| Past tense throughout | No "will be", "will evaluate" in paper sections |
| `paper-figures.md` lists 6 figures | Count of `### Figure` headers = 6 |
| Chart file names match `results/week6/charts/` | `ls results/week6/charts/` agrees |
| All `[CSV]` filled in paper-results-section | After experiments: 0 `[CSV]` remaining |

---

## Task 6 — Demo Preparation

```bash
# 6a. Demo docs exist
ls docs/demo-script.md docs/demo-fallback.md

# 6b. demo.sh is executable
chmod +x scripts/demo.sh
bash -n scripts/demo.sh && echo "Syntax OK"

# 6c. Backup assets folder structure
ls -R results/week7/demo-backup/
# Expected (after dry-run):
#   node-labels.txt
#   pods-default.txt
#   pods-energy-aware.txt
#   scoring-log.txt
#   charts/ (5 PNGs)

# 6d. Dry-run demo (non-interactive check)
# Read the script without executing interactive pauses:
grep "^kubectl\|^python3\|^bash" scripts/demo.sh | head -20
```

### Pass criteria

| Check | Pass condition |
|:---|:---|
| `demo-script.md` present | File exists |
| `demo-fallback.md` present | File exists with backup commands |
| `scripts/demo.sh` syntax valid | `bash -n` exits 0 |
| `results/week7/demo-backup/` populated | All 4 txt files + 5 chart PNGs present |
| `docs/viva-questions.md` has 15 questions | `grep -c "^### Q" docs/viva-questions.md` → 15 |

---

## Final Sign-Off

```bash
# One-shot final check
echo "=== deltas.csv ===" && wc -l results/week7/deltas.csv
echo "=== summary.csv ===" && wc -l results/week6/summary.csv
echo "=== Charts ===" && ls results/week6/charts/
echo "=== Paper docs ===" && ls docs/paper-*.md
echo "=== Demo backup ===" && ls results/week7/demo-backup/ 2>/dev/null || echo "NOT POPULATED YET"
echo "=== Attribution ===" && grep -c "Original Work" docs/contribution.md
echo "=== Secrets check ===" && git ls-files | grep -i "password\|kubeconfig" | wc -l
```

### All-pass conditions

| Item | Expected |
|:---|:---|
| `deltas.csv` lines | ≥ 13 (header + ≥12 data rows) |
| `summary.csv` lines | 9 (header + 8 rows) |
| Charts folder | ≥ 5 PNGs |
| Paper docs | 4 files (implementation, results, edits, figures) |
| Demo backup | Populated (txt files + charts) |
| Attribution | ≥ 1 "Original Work" section |
| Secrets committed | 0 |
