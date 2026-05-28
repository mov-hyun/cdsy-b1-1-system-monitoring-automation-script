#!/usr/bin/env bash

# 명령 실패, 미정의 변수 사용, 파이프라인 실패를 엄격하게 처리한다.
set -euo pipefail

# 압축 대상 로그가 있는 원본 디렉토리다.
LOG_DIR="${LOG_DIR:-/var/log/agent-app}"
# 압축된 로그를 보관할 아카이브 디렉토리다.
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
# 이 일수보다 오래된 *.log 파일을 압축 대상으로 본다.
COMPRESS_DAYS="${COMPRESS_DAYS:-7}"
# 이 일수보다 오래된 *.gz 아카이브 파일을 삭제 대상으로 본다.
DELETE_DAYS="${DELETE_DAYS:-30}"
# 실제 파일 변경 없이 수행 예정 작업만 출력할지 여부다.
DRY_RUN=0

# archive_logs.sh 사용 방법을 출력한다.
usage() {
  # 작은따옴표가 붙은 heredoc이라 변수 치환 없이 설명 문구 그대로 출력된다.
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

# 값이 양의 정수인지 확인한다.
is_positive_integer() {
  # 1 이상의 정수만 허용한다. 0, 음수, 소수, 문자는 실패한다.
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# 전달된 명령행 인자를 순서대로 해석한다.
while [[ $# -gt 0 ]]; do
  # 현재 인자 값에 따라 처리할 옵션을 분기한다.
  case "$1" in
    --log-dir)
      # --log-dir 뒤에 디렉토리 경로가 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 원본 로그 디렉토리를 사용자가 지정한 값으로 바꾼다.
      LOG_DIR="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --archive-dir)
      # --archive-dir 뒤에 디렉토리 경로가 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 아카이브 디렉토리를 사용자가 지정한 값으로 바꾼다.
      ARCHIVE_DIR="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --compress-days)
      # --compress-days 뒤에 일수 값이 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 압축 기준 일수를 사용자가 지정한 값으로 바꾼다.
      COMPRESS_DAYS="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --delete-days)
      # --delete-days 뒤에 일수 값이 있는지 확인한다.
      require_value "$1" "${2:-}"
      # 삭제 기준 일수를 사용자가 지정한 값으로 바꾼다.
      DELETE_DAYS="$2"
      # 옵션 이름과 옵션 값을 모두 소비한다.
      shift 2
      ;;
    --dry-run)
      # 파일을 실제로 바꾸지 않고 수행 예정 작업만 출력하도록 설정한다.
      DRY_RUN=1
      # 옵션 이름 하나만 소비한다.
      shift
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

# 압축 기준 일수가 양의 정수인지 검증한다.
if ! is_positive_integer "$COMPRESS_DAYS"; then
  # 잘못된 일수 입력 오류를 표준 에러로 출력한다.
  echo "[ERROR] --compress-days must be a positive integer." >&2
  # 실패 종료한다.
  exit 1
fi

# 삭제 기준 일수가 양의 정수인지 검증한다.
if ! is_positive_integer "$DELETE_DAYS"; then
  # 잘못된 일수 입력 오류를 표준 에러로 출력한다.
  echo "[ERROR] --delete-days must be a positive integer." >&2
  # 실패 종료한다.
  exit 1
fi

# 원본 로그 디렉토리가 없으면 보관할 대상도 없으므로 안전하게 종료한다.
if [[ ! -d "$LOG_DIR" ]]; then
  # 디렉토리 없음은 장애가 아니라 처리할 대상 없음으로 보고 경고만 출력한다.
  echo "[WARNING] Log directory does not exist: ${LOG_DIR}"
  # 안전 종료한다.
  exit 0
fi

# 원본 로그 디렉토리를 읽을 수 없으면 대상 검색이 불가능하다.
if [[ ! -r "$LOG_DIR" ]]; then
  # 읽기 권한 없음 오류를 표준 에러로 출력한다.
  echo "[ERROR] Log directory is not readable: ${LOG_DIR}" >&2
  # 실패 종료한다.
  exit 1
fi

# dry-run이 아니면 아카이브 디렉토리를 실제로 생성한다.
if (( DRY_RUN == 0 )); then
  # 아카이브 디렉토리가 없으면 생성한다.
  mkdir -p "$ARCHIVE_DIR"
fi

# 아카이브 디렉토리가 없으면 더 진행할 수 없으므로 안전하게 종료한다.
if [[ ! -d "$ARCHIVE_DIR" ]]; then
  # dry-run 등으로 디렉토리가 만들어지지 않은 상황을 경고로 알린다.
  echo "[WARNING] Archive directory does not exist: ${ARCHIVE_DIR}"
  # 안전 종료한다.
  exit 0
fi

# 아카이브 디렉토리에 쓸 수 없으면 압축 파일을 저장할 수 없다.
if [[ ! -w "$ARCHIVE_DIR" ]]; then
  # 쓰기 권한 없음 오류를 표준 에러로 출력한다.
  echo "[ERROR] Archive directory is not writable: ${ARCHIVE_DIR}" >&2
  # 실패 종료한다.
  exit 1
fi

# 기준 일수보다 오래된 *.log 파일을 gzip으로 압축해 아카이브 디렉토리로 이동한다.
compress_old_logs() {
  # 처리 중 사용할 파일 경로, 파일명, 시각, 아카이브 경로, 처리 개수를 선언한다.
  local file basename timestamp archive_file count=0
  # find -mtime은 +N일 때 N보다 큰 값을 찾으므로, 7일 이상을 표현하기 위해 6을 사용한다.
  local mtime_filter=$((COMPRESS_DAYS - 1))

  # 원본 로그 디렉토리 바로 아래의 오래된 *.log 파일을 null 구분자로 안전하게 읽는다.
  while IFS= read -r -d '' file; do
    # 처리 대상 파일 수를 1 증가시킨다.
    count=$((count + 1))
    # 전체 경로에서 파일명만 추출한다.
    basename="$(basename "$file")"
    # 아카이브 파일명 충돌을 줄이기 위해 현재 시각을 붙인다.
    timestamp="$(date '+%Y%m%d%H%M%S')"
    # 최종 아카이브 파일 경로를 만든다. $$는 현재 스크립트 프로세스 PID다.
    archive_file="${ARCHIVE_DIR}/${basename}.${timestamp}.$$.gz"

    # dry-run이면 실제 압축/삭제 없이 예정 작업만 출력한다.
    if (( DRY_RUN )); then
      # 압축 예정 작업을 출력한다.
      echo "[DRY-RUN] Compress ${file} -> ${archive_file}"
      # 다음 파일로 넘어간다.
      continue
    fi

    # 원본 로그를 gzip 형식으로 압축해 아카이브 파일에 저장한다.
    gzip -c "$file" > "$archive_file"
    # 압축이 끝난 원본 로그 파일을 삭제한다.
    rm -f "$file"
    # 아카이브 파일 그룹을 agent-core로 맞춘다. 실패해도 전체 처리는 계속한다.
    chgrp agent-core "$archive_file" 2>/dev/null || true
    # 아카이브 파일 권한을 640으로 맞춘다. 실패해도 전체 처리는 계속한다.
    chmod 640 "$archive_file" 2>/dev/null || true
    # 압축 완료 메시지를 출력한다.
    echo "[INFO] Archived: ${file} -> ${archive_file}"
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$mtime_filter" -print0)

  # 처리 대상이 하나도 없으면 안전하게 정보 메시지만 출력한다.
  if (( count == 0 )); then
    # 오래된 로그가 없다는 메시지를 출력한다.
    echo "[INFO] No *.log files older than ${COMPRESS_DAYS} days in ${LOG_DIR}."
  fi
}

# 기준 일수보다 오래된 *.gz 아카이브 파일을 삭제한다.
delete_old_archives() {
  # 처리 중 사용할 파일 경로와 처리 개수를 선언한다.
  local file count=0
  # find -mtime은 +N일 때 N보다 큰 값을 찾으므로, 30일 이상을 표현하기 위해 29를 사용한다.
  local mtime_filter=$((DELETE_DAYS - 1))

  # 아카이브 디렉토리 바로 아래의 오래된 *.gz 파일을 null 구분자로 안전하게 읽는다.
  while IFS= read -r -d '' file; do
    # 처리 대상 파일 수를 1 증가시킨다.
    count=$((count + 1))

    # dry-run이면 실제 삭제 없이 예정 작업만 출력한다.
    if (( DRY_RUN )); then
      # 삭제 예정 작업을 출력한다.
      echo "[DRY-RUN] Delete old archive ${file}"
      # 다음 파일로 넘어간다.
      continue
    fi

    # 오래된 아카이브 파일을 삭제한다.
    rm -f "$file"
    # 삭제 완료 메시지를 출력한다.
    echo "[INFO] Deleted old archive: ${file}"
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +"$mtime_filter" -print0)

  # 처리 대상이 하나도 없으면 안전하게 정보 메시지만 출력한다.
  if (( count == 0 )); then
    # 오래된 아카이브가 없다는 메시지를 출력한다.
    echo "[INFO] No archived *.gz files older than ${DELETE_DAYS} days in ${ARCHIVE_DIR}."
  fi
}

# 스크립트의 전체 실행 흐름을 담당한다.
main() {
  # 실행 결과 제목을 출력한다.
  echo "====== LOG ARCHIVE RESULT ======"
  # 현재 원본 로그 디렉토리를 출력한다.
  echo "Log directory     : ${LOG_DIR}"
  # 현재 아카이브 디렉토리를 출력한다.
  echo "Archive directory : ${ARCHIVE_DIR}"
  # 현재 압축 정책을 출력한다.
  echo "Compress policy   : *.log older than ${COMPRESS_DAYS} days"
  # 현재 삭제 정책을 출력한다.
  echo "Delete policy     : *.gz older than ${DELETE_DAYS} days"
  # 제목 영역 뒤에 빈 줄을 출력한다.
  echo

  # 오래된 로그를 압축해 아카이브로 이동한다.
  compress_old_logs
  # 오래된 아카이브 파일을 삭제한다.
  delete_old_archives
}

# 스크립트 실행 시 main 함수에 모든 인자를 전달한다.
main "$@"
