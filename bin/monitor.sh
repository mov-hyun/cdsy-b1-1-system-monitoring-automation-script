#!/usr/bin/env bash

set -euo pipefail

APP_PATTERN="${APP_PATTERN:-agent-app-linux-arm64}"
APP_PORT="${APP_PORT:-15034}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_DIR}/monitor.log"

CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

MAX_LOG_BYTES="${MAX_LOG_BYTES:-10485760}"
MAX_LOG_FILES="${MAX_LOG_FILES:-10}"

umask 007

print_header() {
  echo "====== SYSTEM MONITOR RESULT ======"
  echo
}

find_agent_pid() {
  local pid

  pid="$(ps -eo pid=,comm=,args= | awk -v pattern="$APP_PATTERN" '
    $0 ~ pattern && $0 !~ /monitor[.]sh/ && $2 !~ /^(sudo|bash|sh|env|awk)$/ { print $1; exit }
  ')"
  printf '%s\n' "$pid"
}

check_process() {
  local pid="$1"

  if [[ -z "$pid" ]]; then
    echo "Checking process '${APP_PATTERN}'... [FAIL]"
    echo "[ERROR] Agent process is not running."
    exit 1
  fi

  echo "Checking process '${APP_PATTERN}'... [OK] (PID: ${pid})"
}

check_port() {
  if ss -H -tuln | awk -v port="$APP_PORT" '
    $1 == "tcp" && $2 == "LISTEN" {
      local_addr=$5
      sub(/^.*:/, "", local_addr)
      if (local_addr == port) {
        found=1
      }
    }
    END { exit found ? 0 : 1 }
  '; then
    echo "Checking port ${APP_PORT}... [OK]"
    return
  fi

  echo "Checking port ${APP_PORT}... [FAIL]"
  echo "[ERROR] TCP port ${APP_PORT} is not in LISTEN state."
  exit 1
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "Checking firewall... [OK] (UFW active)"
    return
  fi

  if [[ -r /etc/ufw/ufw.conf ]] && grep -Eq '^ENABLED=yes$' /etc/ufw/ufw.conf; then
    echo "Checking firewall... [OK] (UFW enabled)"
    return
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
    echo "Checking firewall... [OK] (ufw service active)"
    return
  fi

  echo "[WARNING] Firewall is inactive or cannot be verified."
}

read_cpu_times() {
  awk '/^cpu / {
    idle=$5 + $6
    non_idle=$2 + $3 + $4 + $7 + $8 + $9
    total=idle + non_idle
    print idle, total
  }' /proc/stat
}

get_cpu_usage() {
  local idle1 total1 idle2 total2 idle_diff total_diff

  read -r idle1 total1 < <(read_cpu_times)
  sleep 1
  read -r idle2 total2 < <(read_cpu_times)

  idle_diff=$((idle2 - idle1))
  total_diff=$((total2 - total1))

  awk -v idle="$idle_diff" -v total="$total_diff" 'BEGIN {
    if (total <= 0) {
      printf "0.0"
    } else {
      printf "%.1f", ((total - idle) * 100) / total
    }
  }'
}

get_mem_usage() {
  awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      if (total <= 0) {
        printf "0.0"
      } else {
        printf "%.1f", ((total - available) * 100) / total
      }
    }
  ' /proc/meminfo
}

get_disk_usage() {
  df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

float_gt() {
  awk -v value="$1" -v threshold="$2" 'BEGIN { exit(value > threshold ? 0 : 1) }'
}

warn_if_needed() {
  local cpu_usage="$1"
  local mem_usage="$2"
  local disk_usage="$3"

  if float_gt "$cpu_usage" "$CPU_THRESHOLD"; then
    echo "[WARNING] CPU threshold exceeded (${cpu_usage}% > ${CPU_THRESHOLD}%)"
  fi

  if float_gt "$mem_usage" "$MEM_THRESHOLD"; then
    echo "[WARNING] MEM threshold exceeded (${mem_usage}% > ${MEM_THRESHOLD}%)"
  fi

  if float_gt "$disk_usage" "$DISK_THRESHOLD"; then
    echo "[WARNING] DISK threshold exceeded (${disk_usage}% > ${DISK_THRESHOLD}%)"
  fi
}

prepare_log_file() {
  if [[ ! -d "$LOG_DIR" ]]; then
    echo "[ERROR] Log directory does not exist: ${LOG_DIR}"
    exit 1
  fi

  if [[ ! -w "$LOG_DIR" ]]; then
    echo "[ERROR] Log directory is not writable: ${LOG_DIR}"
    exit 1
  fi

  touch "$LOG_FILE"
  chgrp agent-core "$LOG_FILE" 2>/dev/null || true
  chmod 660 "$LOG_FILE" 2>/dev/null || true
}

rotate_logs() {
  local size

  prepare_log_file

  size="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if (( size < MAX_LOG_BYTES )); then
    return
  fi

  rm -f "${LOG_FILE}.${MAX_LOG_FILES}"

  for ((i = MAX_LOG_FILES - 1; i >= 1; i--)); do
    if [[ -f "${LOG_FILE}.${i}" ]]; then
      mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    fi
  done

  mv "$LOG_FILE" "${LOG_FILE}.1"
  touch "$LOG_FILE"
  chgrp agent-core "$LOG_FILE" 2>/dev/null || true
  chmod 660 "$LOG_FILE" 2>/dev/null || true
}

append_log() {
  local pid="$1"
  local cpu_usage="$2"
  local mem_usage="$3"
  local disk_usage="$4"
  local timestamp

  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[${timestamp}] PID:${pid} CPU:${cpu_usage}% MEM:${mem_usage}% DISK_USED:${disk_usage}%" >> "$LOG_FILE"
  echo
  echo "[INFO] Log appended: ${LOG_FILE}"
}

main() {
  local pid cpu_usage mem_usage disk_usage

  print_header

  echo "[HEALTH CHECK]"
  pid="$(find_agent_pid)"
  check_process "$pid"
  check_port
  check_firewall
  echo

  echo "[RESOURCE MONITORING]"
  cpu_usage="$(get_cpu_usage)"
  mem_usage="$(get_mem_usage)"
  disk_usage="$(get_disk_usage)"

  echo "CPU Usage : ${cpu_usage}%"
  echo "MEM Usage : ${mem_usage}%"
  echo "DISK Used : ${disk_usage}%"
  echo

  warn_if_needed "$cpu_usage" "$mem_usage" "$disk_usage"

  rotate_logs
  append_log "$pid" "$cpu_usage" "$mem_usage" "$disk_usage"
}

main "$@"
