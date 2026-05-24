#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
COMPRESS_DAYS="${COMPRESS_DAYS:-7}"
DELETE_DAYS="${DELETE_DAYS:-30}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: archive_logs.sh [--log-dir PATH] [--archive-dir PATH] [--compress-days DAYS] [--delete-days DAYS] [--dry-run]

Options:
  --log-dir PATH        Source log directory. Default: /var/log/agent-app
  --archive-dir PATH    Archive directory. Default: /var/log/monitor/agent-app/archive
  --compress-days DAYS  Compress *.log files older than DAYS. Default: 7
  --delete-days DAYS    Delete archived *.gz files older than DAYS. Default: 30
  --dry-run             Print actions without changing files.
  -h, --help            Show this help.
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

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir)
      require_value "$1" "${2:-}"
      LOG_DIR="$2"
      shift 2
      ;;
    --archive-dir)
      require_value "$1" "${2:-}"
      ARCHIVE_DIR="$2"
      shift 2
      ;;
    --compress-days)
      require_value "$1" "${2:-}"
      COMPRESS_DAYS="$2"
      shift 2
      ;;
    --delete-days)
      require_value "$1" "${2:-}"
      DELETE_DAYS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

if ! is_positive_integer "$COMPRESS_DAYS"; then
  echo "[ERROR] --compress-days must be a positive integer." >&2
  exit 1
fi

if ! is_positive_integer "$DELETE_DAYS"; then
  echo "[ERROR] --delete-days must be a positive integer." >&2
  exit 1
fi

if [[ ! -d "$LOG_DIR" ]]; then
  echo "[WARNING] Log directory does not exist: ${LOG_DIR}"
  exit 0
fi

if [[ ! -r "$LOG_DIR" ]]; then
  echo "[ERROR] Log directory is not readable: ${LOG_DIR}" >&2
  exit 1
fi

if (( DRY_RUN == 0 )); then
  mkdir -p "$ARCHIVE_DIR"
fi

if [[ ! -d "$ARCHIVE_DIR" ]]; then
  echo "[WARNING] Archive directory does not exist: ${ARCHIVE_DIR}"
  exit 0
fi

if [[ ! -w "$ARCHIVE_DIR" ]]; then
  echo "[ERROR] Archive directory is not writable: ${ARCHIVE_DIR}" >&2
  exit 1
fi

compress_old_logs() {
  local file basename timestamp archive_file count=0
  local mtime_filter=$((COMPRESS_DAYS - 1))

  while IFS= read -r -d '' file; do
    count=$((count + 1))
    basename="$(basename "$file")"
    timestamp="$(date '+%Y%m%d%H%M%S')"
    archive_file="${ARCHIVE_DIR}/${basename}.${timestamp}.$$.gz"

    if (( DRY_RUN )); then
      echo "[DRY-RUN] Compress ${file} -> ${archive_file}"
      continue
    fi

    gzip -c "$file" > "$archive_file"
    rm -f "$file"
    chgrp agent-core "$archive_file" 2>/dev/null || true
    chmod 640 "$archive_file" 2>/dev/null || true
    echo "[INFO] Archived: ${file} -> ${archive_file}"
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$mtime_filter" -print0)

  if (( count == 0 )); then
    echo "[INFO] No *.log files older than ${COMPRESS_DAYS} days in ${LOG_DIR}."
  fi
}

delete_old_archives() {
  local file count=0
  local mtime_filter=$((DELETE_DAYS - 1))

  while IFS= read -r -d '' file; do
    count=$((count + 1))

    if (( DRY_RUN )); then
      echo "[DRY-RUN] Delete old archive ${file}"
      continue
    fi

    rm -f "$file"
    echo "[INFO] Deleted old archive: ${file}"
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +"$mtime_filter" -print0)

  if (( count == 0 )); then
    echo "[INFO] No archived *.gz files older than ${DELETE_DAYS} days in ${ARCHIVE_DIR}."
  fi
}

main() {
  echo "====== LOG ARCHIVE RESULT ======"
  echo "Log directory     : ${LOG_DIR}"
  echo "Archive directory : ${ARCHIVE_DIR}"
  echo "Compress policy   : *.log older than ${COMPRESS_DAYS} days"
  echo "Delete policy     : *.gz older than ${DELETE_DAYS} days"
  echo

  compress_old_logs
  delete_old_archives
}

main "$@"
