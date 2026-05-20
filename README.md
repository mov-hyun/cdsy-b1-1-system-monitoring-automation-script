# Linux System Monitoring Assignment

This repository is for the AI/SW Linux and OS assignment: system monitoring automation script development.

## Scope

- Configure SSH hardening and firewall rules in an Ubuntu Linux VM.
- Create role-based users, groups, directories, and permissions.
- Run the provided Agent application with required environment variables.
- Implement `monitor.sh` in Bash for process, port, resource, warning, and log checks.
- Document command history, configuration evidence, and cron verification.

## Provided App

The assignment app binaries are stored under `agent-app/`.

- `agent-app`: Linux x86-64 binary
- `agent-app-linux-arm64`: Linux ARM64 binary

For an Apple Silicon Mac mini VM, use Ubuntu Server ARM64 and run `agent-app-linux-arm64`.

## Planned Repository Layout

```text
.
├── agent-app/
├── docs/
│   └── submission-report.md
├── evidence/
│   └── README.md
└── scripts/
    └── monitor.sh
```

`scripts/monitor.sh` will be written after the Linux VM environment is ready.
