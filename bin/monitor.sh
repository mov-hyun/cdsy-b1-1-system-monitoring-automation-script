#!/usr/bin/env bash

# TODO: Implement system monitoring script step by step.
# Requirements:
# - Check Agent app process health.
# - Check TCP port 15034 LISTEN state.
# - Warn when firewall is inactive.
# - Collect CPU, memory, and root disk usage.
# - Append one line to /var/log/agent-app/monitor.log.
# - Keep monitor.log within a 10MB/10-file rotation policy.

set -euo pipefail

main() {
  echo "TODO: monitor.sh implementation will be added during the exercise."
}

main "$@"
