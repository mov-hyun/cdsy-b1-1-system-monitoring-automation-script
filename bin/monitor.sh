#!/usr/bin/env bash

# 명령 실패, 미정의 변수 사용, 파이프라인 실패를 엄격하게 처리한다.
set -euo pipefail

# 감시할 앱 프로세스 식별 문자열이다. 환경 변수 APP_PATTERN이 있으면 그 값을 우선 사용한다.
APP_PATTERN="${APP_PATTERN:-agent-app-linux-arm64}"
# 감시할 TCP 포트다. 과제 기준 Agent 앱 포트는 15034이다.
APP_PORT="${APP_PORT:-15034}"
# 로그 디렉토리다. AGENT_LOG_DIR이 없으면 과제 기본 경로를 사용한다.
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
# 실제 monitor 로그 파일 경로다.
LOG_FILE="${LOG_DIR}/monitor.log"

# CPU 경고 기준이다. CPU 사용률이 20%를 초과하면 WARNING을 출력한다.
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
# 메모리 경고 기준이다. 메모리 사용률이 10%를 초과하면 WARNING을 출력한다.
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
# 디스크 경고 기준이다. 루트 파티션 사용률이 80%를 초과하면 WARNING을 출력한다.
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

# monitor.log 회전 기준 크기다. 10MB는 10 * 1024 * 1024 = 10485760 bytes이다.
MAX_LOG_BYTES="${MAX_LOG_BYTES:-10485760}"
# 보관할 회전 로그 파일 개수다. monitor.log.1부터 monitor.log.10까지 유지한다.
MAX_LOG_FILES="${MAX_LOG_FILES:-10}"

# 새로 만드는 파일에서 others 권한을 기본적으로 제거한다.
umask 007

# 콘솔 출력의 시작 제목을 출력한다.
print_header() {
  # 스크립트 실행 결과 구분선을 출력한다.
  echo "====== SYSTEM MONITOR RESULT ======"
  # 제목 아래에 빈 줄을 출력한다.
  echo
}

# Agent 앱 프로세스의 PID를 찾는다.
find_agent_pid() {
  # 함수 내부에서 사용할 PID 변수를 선언한다.
  local pid

  # ps 결과에서 대상 앱 문자열을 포함하는 실제 앱 프로세스를 찾는다.
  pid="$(ps -eo pid=,comm=,args= | awk -v pattern="$APP_PATTERN" '
    # monitor.sh 자신이나 sudo/bash/env/awk 같은 실행 보조 프로세스는 제외한다.
    $0 ~ pattern && $0 !~ /monitor[.]sh/ && $2 !~ /^(sudo|bash|sh|env|awk)$/ { print $1; exit }
  ')"
  # 찾은 PID를 출력한다. 없으면 빈 문자열이 출력된다.
  printf '%s\n' "$pid"
}

# 앱 프로세스가 실행 중인지 확인한다.
check_process() {
  # 첫 번째 인자로 전달받은 PID를 지역 변수에 저장한다.
  local pid="$1"

  # PID가 비어 있으면 앱 프로세스가 없다는 뜻이다.
  if [[ -z "$pid" ]]; then
    # 프로세스 점검 실패 메시지를 출력한다.
    echo "Checking process '${APP_PATTERN}'... [FAIL]"
    # 실패 원인을 출력한다.
    echo "[ERROR] Agent process is not running."
    # Health Check 실패이므로 종료 코드 1로 종료한다.
    exit 1
  fi

  # PID가 있으면 프로세스 점검 성공 메시지를 출력한다.
  echo "Checking process '${APP_PATTERN}'... [OK] (PID: ${pid})"
}

# Agent 앱 포트가 TCP LISTEN 상태인지 확인한다.
check_port() {
  # ss로 TCP LISTEN 소켓을 조회하고 awk로 포트 번호를 정확히 비교한다.
  if ss -H -tuln | awk -v port="$APP_PORT" '
    # TCP이면서 LISTEN 상태인 행만 검사한다.
    $1 == "tcp" && $2 == "LISTEN" {
      # ss 출력의 로컬 주소:포트 값을 가져온다.
      local_addr=$5
      # 마지막 콜론 앞의 주소 부분을 제거해 포트 번호만 남긴다.
      sub(/^.*:/, "", local_addr)
      # 추출한 포트 번호가 감시 대상 포트와 같으면 찾음 상태로 표시한다.
      if (local_addr == port) {
        found=1
      }
    }
    # 찾았으면 awk를 성공 종료하고, 못 찾았으면 실패 종료한다.
    END { exit found ? 0 : 1 }
  '; then
    # 포트가 열려 있으면 성공 메시지를 출력한다.
    echo "Checking port ${APP_PORT}... [OK]"
    # 함수 실행을 정상 종료한다.
    return
  fi

  # 포트가 LISTEN 상태가 아니면 실패 메시지를 출력한다.
  echo "Checking port ${APP_PORT}... [FAIL]"
  # 실패 원인을 출력한다.
  echo "[ERROR] TCP port ${APP_PORT} is not in LISTEN state."
  # Health Check 실패이므로 종료 코드 1로 종료한다.
  exit 1
}

# 방화벽 활성화 상태를 확인한다. 비활성은 경고만 출력하고 종료하지 않는다.
check_firewall() {
  # ufw 명령이 있고 ufw status 결과가 active이면 방화벽 활성 상태로 본다.
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    # UFW 활성 상태 메시지를 출력한다.
    echo "Checking firewall... [OK] (UFW active)"
    # 더 확인할 필요가 없으므로 함수 실행을 종료한다.
    return
  fi

  # 일반 계정에서 ufw status가 제한될 수 있으므로 설정 파일도 확인한다.
  if [[ -r /etc/ufw/ufw.conf ]] && grep -Eq '^ENABLED=yes$' /etc/ufw/ufw.conf; then
    # UFW 설정 파일 기준 활성 상태 메시지를 출력한다.
    echo "Checking firewall... [OK] (UFW enabled)"
    # 함수 실행을 정상 종료한다.
    return
  fi

  # systemctl이 있고 ufw 서비스가 active이면 방화벽 활성 상태로 본다.
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
    # ufw 서비스 활성 상태 메시지를 출력한다.
    echo "Checking firewall... [OK] (ufw service active)"
    # 함수 실행을 정상 종료한다.
    return
  fi

  # 방화벽 상태를 확인할 수 없거나 비활성 상태면 경고만 출력한다.
  echo "[WARNING] Firewall is inactive or cannot be verified."
}

# /proc/stat에서 전체 CPU의 idle 시간과 total 시간을 읽는다.
read_cpu_times() {
  # /proc/stat의 cpu 행을 읽어 idle과 total 누적 시간을 계산한다.
  awk '/^cpu / {
    # idle은 idle 시간과 iowait 시간을 합친 값이다.
    idle=$5 + $6
    # non_idle은 user, nice, system, irq, softirq, steal 시간을 합친 값이다.
    non_idle=$2 + $3 + $4 + $7 + $8 + $9
    # total은 idle과 non_idle을 합친 전체 CPU 시간이다.
    total=idle + non_idle
    # 호출한 쪽에서 계산할 수 있도록 idle과 total을 출력한다.
    print idle, total
  }' /proc/stat
}

# 1초 간격의 CPU 누적값 차이를 이용해 CPU 사용률을 계산한다.
get_cpu_usage() {
  # 첫 번째/두 번째 측정값과 차이값을 담을 지역 변수를 선언한다.
  local idle1 total1 idle2 total2 idle_diff total_diff

  # 첫 번째 CPU idle/total 값을 읽는다.
  read -r idle1 total1 < <(read_cpu_times)
  # CPU 사용률 계산을 위해 1초 동안 기다린다.
  sleep 1
  # 두 번째 CPU idle/total 값을 읽는다.
  read -r idle2 total2 < <(read_cpu_times)

  # 두 측정 시점 사이의 idle 증가량을 계산한다.
  idle_diff=$((idle2 - idle1))
  # 두 측정 시점 사이의 total 증가량을 계산한다.
  total_diff=$((total2 - total1))

  # CPU 사용률을 소수점 1자리로 계산해 출력한다.
  awk -v idle="$idle_diff" -v total="$total_diff" 'BEGIN {
    # total 증가량이 없으면 0.0으로 처리해 0 나누기를 피한다.
    if (total <= 0) {
      printf "0.0"
    } else {
      # 사용률 = (전체 증가량 - idle 증가량) / 전체 증가량 * 100
      printf "%.1f", ((total - idle) * 100) / total
    }
  }'
}

# /proc/meminfo를 이용해 메모리 사용률을 계산한다.
get_mem_usage() {
  # MemTotal과 MemAvailable을 읽어 사용률을 계산한다.
  awk '
    # 전체 메모리 크기를 KB 단위로 저장한다.
    /^MemTotal:/ { total=$2 }
    # 현재 사용 가능한 메모리 크기를 KB 단위로 저장한다.
    /^MemAvailable:/ { available=$2 }
    # 파일을 모두 읽은 뒤 최종 사용률을 계산한다.
    END {
      # total 값이 없거나 0이면 0.0으로 처리한다.
      if (total <= 0) {
        printf "0.0"
      } else {
        # 사용률 = (전체 메모리 - 사용 가능 메모리) / 전체 메모리 * 100
        printf "%.1f", ((total - available) * 100) / total
      }
    }
  ' /proc/meminfo
}

# 루트 파티션의 디스크 사용률을 계산한다.
get_disk_usage() {
  # df -P / 결과의 두 번째 줄에서 Used% 값을 가져오고 % 기호를 제거한다.
  df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

# 실수 값이 임계값보다 큰지 비교한다.
float_gt() {
  # awk는 실수 비교가 가능하므로 value > threshold이면 성공 종료한다.
  awk -v value="$1" -v threshold="$2" 'BEGIN { exit(value > threshold ? 0 : 1) }'
}

# 수집한 CPU/MEM/DISK 값이 임계값을 넘는지 확인하고 경고를 출력한다.
warn_if_needed() {
  # 첫 번째 인자는 CPU 사용률이다.
  local cpu_usage="$1"
  # 두 번째 인자는 메모리 사용률이다.
  local mem_usage="$2"
  # 세 번째 인자는 디스크 사용률이다.
  local disk_usage="$3"

  # CPU 사용률이 임계값을 초과하면 경고를 출력한다.
  if float_gt "$cpu_usage" "$CPU_THRESHOLD"; then
    # CPU 임계값 초과 경고 메시지다.
    echo "[WARNING] CPU threshold exceeded (${cpu_usage}% > ${CPU_THRESHOLD}%)"
  fi

  # 메모리 사용률이 임계값을 초과하면 경고를 출력한다.
  if float_gt "$mem_usage" "$MEM_THRESHOLD"; then
    # 메모리 임계값 초과 경고 메시지다.
    echo "[WARNING] MEM threshold exceeded (${mem_usage}% > ${MEM_THRESHOLD}%)"
  fi

  # 디스크 사용률이 임계값을 초과하면 경고를 출력한다.
  if float_gt "$disk_usage" "$DISK_THRESHOLD"; then
    # 디스크 임계값 초과 경고 메시지다.
    echo "[WARNING] DISK threshold exceeded (${disk_usage}% > ${DISK_THRESHOLD}%)"
  fi
}

# 로그 파일을 쓰기 전에 디렉토리와 파일 상태를 준비한다.
prepare_log_file() {
  # 로그 디렉토리가 없으면 로그를 쓸 수 없으므로 실패 처리한다.
  if [[ ! -d "$LOG_DIR" ]]; then
    # 로그 디렉토리 없음 오류를 출력한다.
    echo "[ERROR] Log directory does not exist: ${LOG_DIR}"
    # 로그 기록 불가 상태이므로 종료 코드 1로 종료한다.
    exit 1
  fi

  # 로그 디렉토리에 쓰기 권한이 없으면 실패 처리한다.
  if [[ ! -w "$LOG_DIR" ]]; then
    # 로그 디렉토리 쓰기 권한 없음 오류를 출력한다.
    echo "[ERROR] Log directory is not writable: ${LOG_DIR}"
    # 로그 기록 불가 상태이므로 종료 코드 1로 종료한다.
    exit 1
  fi

  # monitor.log 파일이 없으면 생성하고, 있으면 수정 시간만 갱신한다.
  touch "$LOG_FILE"
  # 로그 파일 그룹을 agent-core로 맞춘다. 실패해도 스크립트 전체를 중단하지 않는다.
  chgrp agent-core "$LOG_FILE" 2>/dev/null || true
  # 로그 파일 권한을 660으로 맞춘다. 실패해도 스크립트 전체를 중단하지 않는다.
  chmod 660 "$LOG_FILE" 2>/dev/null || true
}

# monitor.log가 기준 크기 이상이면 10개까지 회전한다.
rotate_logs() {
  # 현재 로그 파일 크기를 저장할 지역 변수를 선언한다.
  local size

  # 로그 파일이 존재하고 쓸 수 있는 상태인지 먼저 확인한다.
  prepare_log_file

  # 현재 monitor.log의 byte 크기를 읽고 공백을 제거한다.
  size="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  # 현재 크기가 기준 크기보다 작으면 회전하지 않는다.
  if (( size < MAX_LOG_BYTES )); then
    # 회전 없이 함수 실행을 종료한다.
    return
  fi

  # 가장 오래된 회전 파일 monitor.log.10을 삭제한다.
  rm -f "${LOG_FILE}.${MAX_LOG_FILES}"

  # monitor.log.9부터 monitor.log.1까지 뒤 번호로 하나씩 밀어낸다.
  for ((i = MAX_LOG_FILES - 1; i >= 1; i--)); do
    # 해당 번호의 회전 파일이 있을 때만 이동한다.
    if [[ -f "${LOG_FILE}.${i}" ]]; then
      # 예: monitor.log.1 -> monitor.log.2
      mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    fi
  done

  # 현재 monitor.log를 monitor.log.1로 이동한다.
  mv "$LOG_FILE" "${LOG_FILE}.1"
  # 새 monitor.log 파일을 만든다.
  touch "$LOG_FILE"
  # 새 로그 파일 그룹을 agent-core로 맞춘다.
  chgrp agent-core "$LOG_FILE" 2>/dev/null || true
  # 새 로그 파일 권한을 660으로 맞춘다.
  chmod 660 "$LOG_FILE" 2>/dev/null || true
}

# 수집한 상태값을 monitor.log에 한 줄로 기록한다.
append_log() {
  # 첫 번째 인자는 앱 PID다.
  local pid="$1"
  # 두 번째 인자는 CPU 사용률이다.
  local cpu_usage="$2"
  # 세 번째 인자는 메모리 사용률이다.
  local mem_usage="$3"
  # 네 번째 인자는 디스크 사용률이다.
  local disk_usage="$4"
  # 현재 시각 문자열을 담을 지역 변수를 선언한다.
  local timestamp

  # 로그 포맷에 사용할 현재 시각을 만든다.
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  # 지정 포맷으로 monitor.log에 한 줄을 누적 기록한다.
  echo "[${timestamp}] PID:${pid} CPU:${cpu_usage}% MEM:${mem_usage}% DISK_USED:${disk_usage}%" >> "$LOG_FILE"
  # 콘솔 출력 가독성을 위해 빈 줄을 출력한다.
  echo
  # 로그 기록 완료 메시지를 출력한다.
  echo "[INFO] Log appended: ${LOG_FILE}"
}

# 스크립트의 전체 실행 흐름을 담당한다.
main() {
  # 앱 PID와 자원 사용률 값을 담을 지역 변수를 선언한다.
  local pid cpu_usage mem_usage disk_usage

  # 결과 제목을 출력한다.
  print_header

  # Health Check 섹션 제목을 출력한다.
  echo "[HEALTH CHECK]"
  # 대상 앱 프로세스 PID를 찾는다.
  pid="$(find_agent_pid)"
  # PID가 있는지 확인하고, 없으면 exit 1로 종료한다.
  check_process "$pid"
  # 대상 포트가 LISTEN 상태인지 확인하고, 아니면 exit 1로 종료한다.
  check_port
  # 방화벽 상태를 확인한다. 문제는 경고만 출력하고 종료하지 않는다.
  check_firewall
  # Health Check 섹션 뒤에 빈 줄을 출력한다.
  echo

  # Resource Monitoring 섹션 제목을 출력한다.
  echo "[RESOURCE MONITORING]"
  # CPU 사용률을 계산한다.
  cpu_usage="$(get_cpu_usage)"
  # 메모리 사용률을 계산한다.
  mem_usage="$(get_mem_usage)"
  # 루트 파티션 디스크 사용률을 계산한다.
  disk_usage="$(get_disk_usage)"

  # CPU 사용률을 콘솔에 출력한다.
  echo "CPU Usage : ${cpu_usage}%"
  # 메모리 사용률을 콘솔에 출력한다.
  echo "MEM Usage : ${mem_usage}%"
  # 디스크 사용률을 콘솔에 출력한다.
  echo "DISK Used : ${disk_usage}%"
  # Resource Monitoring 섹션 뒤에 빈 줄을 출력한다.
  echo

  # 임계값을 초과한 항목이 있으면 WARNING을 출력한다.
  warn_if_needed "$cpu_usage" "$mem_usage" "$disk_usage"

  # 로그 파일 크기가 기준을 넘으면 회전한다.
  rotate_logs
  # 현재 수집 결과를 monitor.log에 기록한다.
  append_log "$pid" "$cpu_usage" "$mem_usage" "$disk_usage"
}

# 스크립트 실행 시 main 함수에 모든 인자를 전달한다.
main "$@"
