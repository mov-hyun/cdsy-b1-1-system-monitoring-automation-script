#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
START_TIME=""
END_TIME=""

usage() {
  cat <<'EOF'
Usage: report.sh [--log-file PATH] [--start "YYYY-MM-DD HH:MM:SS"] [--end "YYYY-MM-DD HH:MM:SS"]

Options:
  --log-file PATH   monitor.log path. Default: ${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log
  --start TIME      Include samples at or after TIME.
  --end TIME        Include samples at or before TIME.
  -h, --help        Show this help.
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[ERROR] Missing value for ${option}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-file)
      require_value "$1" "${2:-}"
      LOG_FILE="$2"
      shift 2
      ;;
    --start)
      require_value "$1" "${2:-}"
      START_TIME="$2"
      shift 2
      ;;
    --end)
      require_value "$1" "${2:-}"
      END_TIME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$LOG_FILE" ]]; then
  echo "[ERROR] Log file does not exist: ${LOG_FILE}" >&2
  exit 1
fi

if [[ ! -r "$LOG_FILE" ]]; then
  echo "[ERROR] Log file is not readable: ${LOG_FILE}" >&2
  exit 1
fi

awk -v start="$START_TIME" -v end="$END_TIME" '
function clean_percent(value) {
  gsub("%", "", value)
  return value + 0
}

function update_metric(metric, value, timestamp) {
  sum[metric] += value

  if (count == 1 || value > max[metric]) {
    max[metric] = value
    max_time[metric] = timestamp
  }

  if (count == 1 || value < min[metric]) {
    min[metric] = value
    min_time[metric] = timestamp
  }
}

function print_metric(title, metric) {
  printf "[%s]\n", title
  printf "Average : %.1f%%\n", sum[metric] / count
  printf "Maximum : %.1f%% at %s\n", max[metric], max_time[metric]
  printf "Minimum : %.1f%% at %s\n", min[metric], min_time[metric]
}

/^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
  timestamp = substr($0, 2, 19)

  if (start != "" && timestamp < start) {
    next
  }

  if (end != "" && timestamp > end) {
    next
  }

  cpu = mem = disk = ""

  for (i = 1; i <= NF; i++) {
    if ($i ~ /^CPU:/) {
      cpu = clean_percent(substr($i, 5))
    } else if ($i ~ /^MEM:/) {
      mem = clean_percent(substr($i, 5))
    } else if ($i ~ /^DISK_USED:/) {
      disk = clean_percent(substr($i, 11))
    }
  }

  if (cpu == "" || mem == "" || disk == "") {
    next
  }

  count++
  update_metric("cpu", cpu, timestamp)
  update_metric("mem", mem, timestamp)
  update_metric("disk", disk, timestamp)
}

END {
  if (count == 0) {
    print "[ERROR] No monitor samples found." > "/dev/stderr"
    exit 1
  }

  print "====== STATISTICS REPORT ======"
  print_metric("CPU", "cpu")
  print_metric("Memory", "mem")
  print_metric("Disk", "disk")
  print "[Samples]"
  printf "Data Points: %d samples\n", count
}
' "$LOG_FILE"
