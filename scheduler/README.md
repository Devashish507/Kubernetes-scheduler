# scheduler/

This directory will contain the `scheduler-plugins` repository.

## Setup

Clone the repository into this directory:

```bash
# Run from the project root inside WSL2 Ubuntu
git clone https://github.com/kubernetes-sigs/scheduler-plugins.git \
  scheduler/scheduler-plugins
```

After cloning, the structure will be:

```text
scheduler/
└── scheduler-plugins/   ← kubernetes-sigs/scheduler-plugins
    ├── cmd/
    │   ├── scheduler/main.go     ← scheduler binary entry point
    │   └── controller/controller.go
    ├── pkg/
    │   ├── trimaran/             ← load-aware scheduling plugin
    │   ├── coscheduling/         ← gang scheduling plugin
    │   └── ...                   ← other plugins
    ├── go.mod                    ← requires go 1.26.0
    ├── Makefile                  ← build targets: make build
    └── README.md
```

## Build

See [../docs/scheduler-build.md](../docs/scheduler-build.md) for full
build instructions.

Quick build:

```bash
cd scheduler/scheduler-plugins
go mod download
make build
# Produces: bin/kube-scheduler  bin/controller
```
