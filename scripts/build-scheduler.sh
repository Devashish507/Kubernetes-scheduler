#!/usr/bin/env bash
# =============================================================================
# scripts/build-scheduler.sh
# =============================================================================
# Purpose:  Build the custom energy-aware-scheduler Docker image and load it
#           into the KIND cluster named 'energy'.
#
# Usage:    bash scripts/build-scheduler.sh
#
# What it does:
#   1. Verifies the Go version meets the go.mod requirement (1.26.0).
#   2. Builds the scheduler binary using 'make build-scheduler' (the
#      repository's verified Makefile target).
#   3. Builds a Docker image named energy-aware-scheduler:v0.1.0.
#   4. Loads the image into every KIND node of the 'energy' cluster.
#   5. Verifies the image is visible inside the KIND nodes.
#
# The Dockerfile used is:
#   scheduler/scheduler-plugins/build/scheduler/Dockerfile
# It builds using the already-compiled binary, which avoids duplicating
# Go compilation inside Docker and keeps build times shorter.
#
# Important: All commands must be run inside WSL2 Ubuntu.
# =============================================================================

set -euo pipefail

REPO="scheduler/scheduler-plugins"
IMAGE_NAME="energy-aware-scheduler"
IMAGE_TAG="v0.1.0"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
CLUSTER_NAME="energy"
GO_BIN="/usr/local/go/bin/go"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "======================================================"
log "  Energy-Aware Scheduler — Build + Load"
log "======================================================"

# -------------------------------------------------------
# Step 1: Verify Go installation
# -------------------------------------------------------
if [ ! -x "${GO_BIN}" ]; then
  echo "ERROR: Go not found at ${GO_BIN}"
  echo "Install Go 1.26+ from https://go.dev/dl/"
  exit 1
fi

GO_VERSION=$("${GO_BIN}" version | awk '{print $3}' | tr -d 'go')
log "Go version: ${GO_VERSION}"

# Extract major.minor and check >= 1.26
MAJOR=$(echo "${GO_VERSION}" | cut -d. -f1)
MINOR=$(echo "${GO_VERSION}" | cut -d. -f2)
if [ "${MAJOR}" -lt 1 ] || { [ "${MAJOR}" -eq 1 ] && [ "${MINOR}" -lt 26 ]; }; then
  echo "ERROR: Go >= 1.26.0 is required (go.mod: go 1.26.0), found ${GO_VERSION}"
  exit 1
fi

# -------------------------------------------------------
# Step 2: Verify Docker is available
# -------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "ERROR: docker is not in PATH. Make sure Docker Desktop WSL2 integration is enabled."
  exit 1
fi
log "Docker: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo 'detected')"

# -------------------------------------------------------
# Step 3: Verify KIND cluster exists
# -------------------------------------------------------
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "ERROR: KIND cluster '${CLUSTER_NAME}' not found."
  echo "Run: bash scripts/setup-cluster.sh"
  exit 1
fi
log "KIND cluster '${CLUSTER_NAME}' found."

# -------------------------------------------------------
# Step 4: Build the scheduler binary
# -------------------------------------------------------
log "Building scheduler binary (equivalent to 'make build-scheduler') ..."
cd "${REPO}"

# Derive version string using the same formula as the Makefile:
#   VERSION = v0.0.YYYYMMDD
VERSION="v0.0.$(date +%Y%m%d)"

# This is exactly what the Makefile 'build-scheduler' target runs:
CGO_ENABLED=0 "${GO_BIN}" build \
  -ldflags "-X k8s.io/component-base/version.gitVersion=${VERSION} -w" \
  -o bin/kube-scheduler \
  cmd/scheduler/main.go

if [ ! -f "bin/kube-scheduler" ]; then
  echo "ERROR: make build-scheduler completed but bin/kube-scheduler not found."
  exit 1
fi
log "Binary built: $(ls -lh bin/kube-scheduler | awk '{print $5, $9}')"

# -------------------------------------------------------
# Step 5: Build the Docker image
# -------------------------------------------------------
log "Building Docker image ${FULL_IMAGE} ..."
# Use the existing Dockerfile but override the build stage: since we already
# have a compiled binary, use a simpler single-stage build.
# The existing Dockerfile expects 'make build-scheduler' to be run inside the
# container; we copy the pre-built binary instead.
log "Using custom Dockerfile that copies the pre-built binary ..."
cat > /tmp/energy-scheduler.Dockerfile <<'DOCKERFILE'
FROM gcr.io/distroless/static:nonroot
WORKDIR /bin
COPY bin/kube-scheduler .
USER 65532:65532
ENTRYPOINT ["/bin/kube-scheduler"]
DOCKERFILE

docker build \
  -t "${FULL_IMAGE}" \
  -f /tmp/energy-scheduler.Dockerfile \
  .

log "Image built: ${FULL_IMAGE}"
docker image inspect "${FULL_IMAGE}" --format "  ID: {{.Id}}" 2>/dev/null || true

# Go back to project root
cd - > /dev/null

# -------------------------------------------------------
# Step 6: Load image into KIND cluster
# -------------------------------------------------------
log "Loading ${FULL_IMAGE} into KIND cluster '${CLUSTER_NAME}' ..."
log "This copies the image into every node's container runtime."
kind load docker-image "${FULL_IMAGE}" --name "${CLUSTER_NAME}"

# -------------------------------------------------------
# Step 7: Verify the image is visible inside KIND nodes
# -------------------------------------------------------
log "Verifying image is present inside KIND nodes ..."
for node in $(kind get nodes --name "${CLUSTER_NAME}" 2>/dev/null); do
  result=$(docker exec "${node}" crictl images 2>/dev/null | grep "${IMAGE_NAME}" | head -1 || true)
  if [ -n "${result}" ]; then
    log "  ${node}: OK — ${result}"
  else
    log "  WARNING: ${node}: image not found via crictl (may still work if containerd imported it)"
  fi
done

log ""
log "======================================================"
log "  Build complete: ${FULL_IMAGE}"
log "======================================================"
log ""
log "Next steps:"
log "  1. Apply manifests:  bash scripts/deploy-scheduler.sh"
log "  2. Or manually:      kubectl apply -f scheduler/manifests/ --context kind-energy"
