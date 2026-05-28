#!/usr/bin/env bash

# 명령 실패, 미정의 변수 사용, 파이프라인 실패를 엄격하게 처리한다.
set -euo pipefail

# 분석할 monitor.log 경로다. AGENT_LOG_DIR이 있으면 그 값을 기준으로 사용한다.
LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
# 선택 분석 시작 시각이다. 비어 있으면 시작 제한 없이 전체 로그를 분석한다.
START_TIME=""
# 선택 분석 종료 시각이다. 비어 있으면 종료 제한 없이 전체 로그를 분석한다.
END_TIME=""

# report.sh 사용 방법을 출력한다.
usage() {
  # 작은따옴표가 붙은 heredoc이라 변수는 실제 값으로 치환되지 않고 설명 문구 그대로 출력된다.
  cat <<'EOF'
Usage: report.sh [--log-file PATH] [--start "YYYY-MM-DD HH:MM:SS"] [--end "YYYY-MM-DD HH:MM:SS"]

Options:
  --log-file PATH   monitor.log path. Default: ${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log
  --start TIME      Include samples at or after TIME.
  --end TIME        Include samples at or before TIME.
  -h, --help        Show this help.
EOF
}

# 옵션 뒤에 필수 값이 전달되었는지 확인한다.
require_value() {
  # 검사 대상 옵션 이름이다.
  local option="$1"
  # 옵션 뒤에 온 값이다. 없으면 빈 문자열로 처리한다.
  local value="${2:-}"

  # 값이 없거나 다음 옵션처럼 --로 시작하면 잘못된 입력으로 본다.
  if [[ -z "$value" || "$value" == --* ]]; then
    # 오류 메시지는 표준 에러로 출력한다.
    echo "[ERROR] Missing value for ${option}" >&2
    # 잘못된 사용법이므로 종료 코드 1로 종료한다.
    exit 1
  fi
}

# 전달된 명령행 인자를 순서대로 해석한다.
while [[ $# -gt 0 ]]; do
  # 현재 인자 값에 따라 처리할 옵션을 분기한다.
  case "$1" in
    --log-file)
      # --log-file 뒤에 파일 경로가 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 분석할 로그 파일 경로를 사용자가 지정한 값으로 바꾼다.
      LOG_FILE="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --start)
      # --start 뒤에 시작 시각 문자열이 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 시작 시각 필터 값을 저장한다.
      START_TIME="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --end)
      # --end 뒤에 종료 시각 문자열이 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 종료 시각 필터 값을 저장한다.
      END_TIME="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    -h|--help)
      # 도움말 옵션이 들어오면 사용법을 출력한다.
      usage
      # 정상 종료한다.
      exit 0
      ;;
    *)
      # 정의하지 않은 옵션은 오류로 처리한다.
      echo "[ERROR] Unknown option: $1" >&2
      # 사용자가 수정할 수 있도록 사용법도 함께 출력한다.
      usage >&2
      # 잘못된 사용법이므로 종료 코드 1로 종료한다.
      exit 1
      ;;
  esac
done

# 분석 대상 로그 파일이 없으면 리포트를 만들 수 없다.
if [[ ! -f "$LOG_FILE" ]]; then
  # 파일 없음 오류를 표준 에러로 출력한다.
  echo "[ERROR] Log file does not exist: ${LOG_FILE}" >&2
  # 실패 종료한다.
  exit 1
fi

# 로그 파일 읽기 권한이 없으면 분석할 수 없다.
if [[ ! -r "$LOG_FILE" ]]; then
  # 읽기 권한 없음 오류를 표준 에러로 출력한다.
  echo "[ERROR] Log file is not readable: ${LOG_FILE}" >&2
  # 실패 종료한다.
  exit 1
fi

# awk로 monitor.log를 한 줄씩 읽으며 CPU/MEM/DISK 통계를 계산한다.
awk -v start="$START_TIME" -v end="$END_TIME" '
# 퍼센트 문자열에서 % 기호를 제거하고 숫자로 변환한다.
function clean_percent(value) {
  # 예: "4.0%" -> "4.0"
  gsub("%", "", value)
  # 숫자 연산이 가능하도록 0을 더해 숫자 타입으로 바꾼다.
  return value + 0
}

# 특정 지표의 합계, 최대값, 최소값을 갱신한다.
function update_metric(metric, value, timestamp) {
  # 평균 계산을 위해 지표별 합계에 현재 값을 더한다.
  sum[metric] += value

  # 첫 샘플이거나 기존 최대값보다 크면 최대값과 시각을 갱신한다.
  if (count == 1 || value > max[metric]) {
    max[metric] = value
    max_time[metric] = timestamp
  }

  # 첫 샘플이거나 기존 최소값보다 작으면 최소값과 시각을 갱신한다.
  if (count == 1 || value < min[metric]) {
    min[metric] = value
    min_time[metric] = timestamp
  }
}

# 특정 지표의 평균, 최대, 최소 결과를 출력한다.
function print_metric(title, metric) {
  # 지표 제목을 출력한다.
  printf "[%s]\n", title
  # 평균은 합계를 샘플 수로 나누어 계산한다.
  printf "Average : %.1f%%\n", sum[metric] / count
  # 최대값과 최대값이 나온 시각을 출력한다.
  printf "Maximum : %.1f%% at %s\n", max[metric], max_time[metric]
  # 최소값과 최소값이 나온 시각을 출력한다.
  printf "Minimum : %.1f%% at %s\n", min[metric], min_time[metric]
}

# monitor.log의 지정 포맷과 일치하는 줄만 분석한다.
/^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
  # 대괄호 안의 시각 부분만 추출한다.
  timestamp = substr($0, 2, 19)

  # 시작 시각이 지정되었고 현재 로그가 그보다 이전이면 건너뛴다.
  if (start != "" && timestamp < start) {
    next
  }

  # 종료 시각이 지정되었고 현재 로그가 그보다 이후이면 건너뛴다.
  if (end != "" && timestamp > end) {
    next
  }

  # 현재 줄에서 추출할 CPU/MEM/DISK 값을 초기화한다.
  cpu = mem = disk = ""

  # 공백으로 분리된 각 필드를 순회하며 필요한 값을 찾는다.
  for (i = 1; i <= NF; i++) {
    # CPU:로 시작하는 필드에서 CPU 사용률을 추출한다.
    if ($i ~ /^CPU:/) {
      cpu = clean_percent(substr($i, 5))
    # MEM:으로 시작하는 필드에서 메모리 사용률을 추출한다.
    } else if ($i ~ /^MEM:/) {
      mem = clean_percent(substr($i, 5))
    # DISK_USED:로 시작하는 필드에서 디스크 사용률을 추출한다.
    } else if ($i ~ /^DISK_USED:/) {
      disk = clean_percent(substr($i, 11))
    }
  }

  # 셋 중 하나라도 추출하지 못한 줄은 통계에서 제외한다.
  if (cpu == "" || mem == "" || disk == "") {
    next
  }

  # 유효한 샘플 수를 1 증가시킨다.
  count++
  # CPU 통계를 갱신한다.
  update_metric("cpu", cpu, timestamp)
  # 메모리 통계를 갱신한다.
  update_metric("mem", mem, timestamp)
  # 디스크 통계를 갱신한다.
  update_metric("disk", disk, timestamp)
}

# 모든 로그 줄을 읽은 뒤 최종 리포트를 출력한다.
END {
  # 유효 샘플이 하나도 없으면 오류로 종료한다.
  if (count == 0) {
    print "[ERROR] No monitor samples found." > "/dev/stderr"
    exit 1
  }

  # 리포트 제목을 출력한다.
  print "====== STATISTICS REPORT ======"
  # CPU 통계를 출력한다.
  print_metric("CPU", "cpu")
  # 메모리 통계를 출력한다.
  print_metric("Memory", "mem")
  # 디스크 통계를 출력한다.
  print_metric("Disk", "disk")
  # 샘플 수 섹션 제목을 출력한다.
  print "[Samples]"
  # 실제 분석에 사용한 샘플 수를 출력한다.
  printf "Data Points: %d samples\n", count
}
' "$LOG_FILE"
