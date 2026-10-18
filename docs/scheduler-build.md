# Scheduler-Plugins: Build Documentation

## 1. Repository Location

The scheduler-plugins repository should be cloned into:

```text
scheduler/scheduler-plugins/
```

from the project root.

**Source:** https://github.com/kubernetes-sigs/scheduler-plugins

Clone command (run from the project root inside WSL2 Ubuntu):

```bash
git clone https://github.com/kubernetes-sigs/scheduler-plugins.git \
  scheduler/scheduler-plugins
```

---

## 2. Required Go Version

The repository's `go.mod` currently specifies:

```
go 1.26.0
```

> **Verified from:** `go.mod` on the `master` branch, September 2026.

Before building, confirm your installed Go version is at least `1.26.0`:

```bash
go version
```

Expected output example:

```
go version go1.26.x linux/amd64
```

If your installed version is older, download the latest Go from
https://go.dev/dl/ and follow the WSL2 installation instructions.

> **Do NOT** modify `go.mod` to work around a version mismatch.
> An older toolchain may silently produce an incorrect binary.

---

## 3. Verified Makefile Targets

The following targets were verified directly from the repository's `Makefile`
(SHA: `c19c163e1c60a4f159f148622784050510d8250a`):

| Target | What it does |
|---|---|
| `make` / `make build` | Builds both `build-scheduler` and `build-controller` |
| `make build-scheduler` | Compiles `cmd/scheduler/main.go` → `bin/kube-scheduler` |
| `make build-controller` | Compiles `cmd/controller/controller.go` → `bin/controller` |
| `make local-image` | Builds a Docker image tagged for local use |
| `make unit-test` | Runs unit tests |
| `make verify` | Runs `go mod` and `go fmt` verification |
| `make clean` | Removes the `bin/` directory |

> **Do NOT** use any target not listed above. The Makefile does not have
> targets such as `install`, `run`, `test-integration` (separate from
> `integration-test`), or `docker-push`.

---

## 4. Build Commands

All commands below must be run **inside WSL2 Ubuntu** from the
`scheduler/scheduler-plugins/` directory.

### Step 4.1 — Clone (if not already done)

From the project root:

```bash
git clone https://github.com/kubernetes-sigs/scheduler-plugins.git \
  scheduler/scheduler-plugins

cd scheduler/scheduler-plugins
```

### Step 4.2 — Verify Go version

```bash
go version
# Must be >= 1.26.0

grep '^go ' go.mod
# Should print:  go 1.26.0
```

### Step 4.3 — Download dependencies

```bash
go mod download
```

This fetches all modules listed in `go.mod`/`go.sum`. It may take a few
minutes on first run.

### Step 4.4 — Build the binaries

```bash
make build
```

This is equivalent to running:

```bash
make build-scheduler
make build-controller
```

The Makefile injects the version string using `ldflags`. Both binaries are
written to `bin/`:

```text
bin/kube-scheduler
bin/controller
```

### Step 4.5 — (Optional) Build only the scheduler binary

```bash
make build-scheduler
```

---

## 5. Expected Successful Build Output

A successful `make build` will produce output similar to:

```
go build -ldflags '-X k8s.io/component-base/version.gitVersion=v0.0.20260925-... -w' \
  -o bin/controller cmd/controller/controller.go
go build -ldflags '-X k8s.io/component-base/version.gitVersion=v0.0.20260925-... -w' \
  -o bin/kube-scheduler cmd/scheduler/main.go
```

No error lines. After the build completes:

```bash
ls -lh bin/
# Expected:
#   bin/controller
#   bin/kube-scheduler
```

Verify the binary runs:

```bash
./bin/kube-scheduler --version
# Expected output (example):
#   Kubernetes v0.0.20260925-...
```

---

## 6. Important Dependencies

The repository depends on the following key packages (from `go.mod`):

| Module | Role |
|---|---|
| `k8s.io/kubernetes v1.36.4` | Core Kubernetes libraries |
| `k8s.io/kube-scheduler v0.36.4` | Scheduler framework |
| `k8s.io/client-go v0.36.4` | Kubernetes API client |
| `k8s.io/api v0.36.4` | Kubernetes API types |
| `sigs.k8s.io/controller-runtime v0.24.1` | Controller library |
| `github.com/paypal/load-watcher v0.2.4` | Used by Trimaran plugin |

> These versions are pinned in `go.sum` and will be downloaded exactly.
> Do not run `go get` to upgrade them unless you understand the compatibility
> matrix (scheduler plugins must match the Kubernetes version exactly).

---

## 7. Troubleshooting

### Problem: `go: toolchain go1.26.0 unavailable`

**Cause:** Your Go installation is older than `1.26.0`.

**Fix:** Download and install Go 1.26+ from https://go.dev/dl/

```bash
# Example for Linux/WSL2:
wget https://go.dev/dl/go1.26.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version
```

---

### Problem: `make: command not found`

**Cause:** `make` is not installed in WSL2 Ubuntu.

**Fix:**

```bash
sudo apt-get update && sudo apt-get install -y build-essential
```

---

### Problem: Network errors downloading modules

**Cause:** Proxy or firewall blocking the Go module proxy.

**Fix:** Try setting the Go proxy explicitly:

```bash
export GOPROXY=https://proxy.golang.org,direct
go mod download
```

---

### Problem: `git describe: No names found, cannot describe anything`

**Cause:** The repository was cloned without tags (shallow clone or no tags).

**Effect:** The `RELEASE_VERSION` variable falls back to
`v0.0.YYYYMMDD`. This does not affect functionality — the binaries are
fully usable.

**Fix (optional):** Fetch tags:

```bash
git fetch --tags
```

---

### Problem: Build succeeds but `bin/` directory is empty

**Cause:** Running the wrong target or from the wrong directory.

**Fix:** Always run `make build` from inside `scheduler/scheduler-plugins/`,
not from the project root.

---

## 8. What the Built Binary Is (and Is Not)

The `bin/kube-scheduler` binary is a **complete Kubernetes scheduler** that
includes all the plugins from the `scheduler-plugins` repository
(Trimaran, Coscheduling, NodeResourceTopology, etc.) in addition to the
standard Kubernetes scheduling plugins.

For Week 1, the build only confirms that the codebase compiles correctly
in your environment. The binary is not deployed to the cluster yet.

Deployment and custom plugin integration are Phase 2 work.
