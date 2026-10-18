#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/go/bin:$PATH
cd /mnt/c/Users/devas/OneDrive/Desktop/schedular/scheduler/scheduler-plugins
VERSION="v0.0.$(date +%Y%m%d)"
echo "[BUILD] Building kube-scheduler binary (version: $VERSION) ..."
CGO_ENABLED=0 go build \
  -ldflags "-X k8s.io/component-base/version.gitVersion=$VERSION -w" \
  -o bin/kube-scheduler \
  cmd/scheduler/main.go
echo "[BUILD] Success: $(ls -lh bin/kube-scheduler)"
