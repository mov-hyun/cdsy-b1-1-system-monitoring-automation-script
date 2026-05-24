# 시스템 관제 자동화 스크립트 개발

> Linux 서버 운영 환경을 구성하고, 제공 Agent 앱의 상태를 Bash 스크립트로 관제하는 과제입니다.

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-monitor.sh-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![UFW](https://img.shields.io/badge/Firewall-UFW-1E88E5?style=flat-square)
![cron](https://img.shields.io/badge/Scheduler-cron-6B7280?style=flat-square)

## 목차

1. [과제 개요](#1-과제-개요)
2. [실습 환경 및 필수 도구 확인](#2-실습-환경-및-필수-도구-확인)
3. [핵심 개념 정리](#3-핵심-개념-정리)
4. [수행 내역](#4-수행-내역)
5. [장애 상황 대응](#5-장애-상황-대응)
6. [보너스 과제](#6-보너스-과제)
7. [트러블슈팅](#7-트러블슈팅)

## 1. 과제 개요

이 과제는 단일 Linux 서버를 운영한다고 가정하고, 기본 보안 설정부터 서비스 실행, 상태 점검, 로그 기록, 자동 실행까지 구성하는 실습입니다.
주요 목표는 다음과 같습니다.

1. SSH 포트를 `20022`로 변경하고 root 원격 접속을 차단한다.
2. UFW 또는 firewalld로 필요한 인바운드 포트만 허용한다.
3. 역할 기반 계정, 그룹, 디렉토리 권한을 구성한다.
4. 제공 Agent 앱을 일반 계정으로 실행한다.
5. Bash 기반 `monitor.sh`로 프로세스, 포트, 리소스 상태를 점검한다.
6. 점검 결과를 `/var/log/agent-app/monitor.log`에 누적 기록한다.
7. cron으로 모니터링을 매분 자동 실행한다.
8. 로그 용량을 10MB/10개 기준으로 관리한다.

### 제출 산출물

1. 요구사항 수행 내역서: 이 `README.md`
2. 자동화 스크립트: `bin/monitor.sh`

보너스 수행 파일: `bin/report.sh`, `bin/archive_logs.sh`

### 레포지토리 구조

```text
.
├── README.md
└── bin/
    ├── archive_logs.sh
    ├── monitor.sh
    └── report.sh
```

레포지토리의 `bin/monitor.sh`는 실습 서버에서 `$AGENT_HOME/bin/monitor.sh`로 배치해 사용하는 파일입니다.
보너스 과제의 `bin/report.sh`, `bin/archive_logs.sh`는 실습 서버에서 `$AGENT_HOME/bin/` 아래로 배치해 사용하는 파일입니다.

### 체크리스트

<details>
<summary>요구사항 체크리스트</summary>

- [x] SSH 포트를 `20022`로 변경했다.
- [x] root 원격 접속을 차단했다.
- [x] 방화벽을 활성화하고 인바운드 허용 포트를 `20022/tcp`, `15034/tcp`로 제한했다.
- [x] `agent-admin`, `agent-dev`, `agent-test` 계정과 `agent-common`, `agent-core` 그룹을 생성했다.
- [x] `agent-common`에는 admin/dev/test를, `agent-core`에는 admin/dev를 포함했다.
- [x] `$AGENT_HOME/upload_files`는 `agent-common`, `$AGENT_HOME/api_keys`와 `/var/log/agent-app`은 `agent-core` 권한으로 구성했다.
- [x] `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 환경 변수를 구성했다.
- [x] 제공 앱 기준 키 파일인 `$AGENT_HOME/api_keys/secret.key`를 생성했다.
- [x] 앱을 일반 계정으로 실행하고 Boot Sequence 5단계 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN 상태를 확인했다.
- [x] `bin/monitor.sh`를 Bash로 구현하고 실습 서버의 `$AGENT_HOME/bin/monitor.sh`에 배치했다.
- [x] `monitor.sh` 소유자/그룹/권한을 `agent-dev:agent-core`, `750`으로 설정했다.
- [x] `monitor.sh`가 앱 프로세스와 `15034/tcp` 포트 비정상 상태에서 `exit 1`로 종료한다.
- [x] `monitor.sh`가 방화벽 비활성, CPU/MEM/DISK 임계값 초과를 `[WARNING]`으로 출력한다.
- [x] `monitor.sh`가 CPU/MEM/DISK 사용률을 수집한다.
- [x] `/var/log/agent-app/monitor.log`에 지정 포맷으로 로그를 누적 기록한다.
- [x] `monitor.log` 10MB/10개 용량 관리 정책을 구현했다.
- [x] `agent-admin` crontab에 `monitor.sh` 매분 실행을 등록하고 1분 후 로그 자동 증가를 확인했다.
- [x] 설정 파일, `ss -tulnp`, `monitor.log` 최근 라인으로 주요 결과를 확인했다.

</details>

---

## 2. 실습 환경 및 필수 도구 확인

Linux 실습 환경과 필수 도구 준비

- 로컬 작업 환경: macOS
- 리눅스 실습 환경: OrbStack Linux Machine
- OS: Ubuntu 24.04.4 LTS (Noble Numbat)
- Architecture: aarch64
- 사용 앱 파일: `agent-app-linux-arm64`

`agent-app/` 디렉토리의 제공 실행 파일은 로컬에만 보관하고 Git에는 올리지 않습니다.

도구별 역할

| 도구 | 의미 | 과제에서 사용하는 이유 |
|---|---|---|
| `sshd` | SSH 접속을 받아주는 서버 데몬 | SSH 포트를 `20022`로 변경하고 root 원격 접속을 차단하기 위해 사용 |
| `systemctl` | Linux 서비스 상태 확인 및 제어 도구 | SSH, cron 같은 백그라운드 서비스를 재시작하거나 상태 확인할 때 사용 |
| `ufw` | Ubuntu 방화벽 관리 도구 | `20022/tcp`, `15034/tcp`만 허용하는 방화벽 정책을 구성하기 위해 사용 |
| `getfacl` | ACL 권한 확인 도구 | 디렉토리와 파일에 적용된 세부 접근 권한을 확인하기 위해 사용 |
| `setfacl` | ACL 권한 설정 도구 | 공유 디렉토리와 보안 디렉토리의 접근 권한을 세밀하게 설정하기 위해 사용 |
| `cron` | 주기적으로 작업을 실행하는 데몬 | `monitor.sh`가 매분 자동 실행되도록 하기 위해 필요 |
| `crontab` | 사용자별 cron 작업 등록 도구 | `agent-admin` 계정의 매분 실행 일정을 등록하고 확인하기 위해 사용 |
| `ss` | 네트워크 소켓 상태 확인 도구 | `sshd`와 Agent 앱이 각각 `20022`, `15034` 포트에서 LISTEN 중인지 확인하기 위해 사용 |

---

## 3. 핵심 개념 정리

### 3.1 SSH 포트 변경과 root 접속 차단

SSH는 원격 서버에 터미널로 접속하기 위한 프로토콜입니다. 기본 포트는 `22/tcp`이지만, 이 과제에서는 `20022/tcp`로 변경합니다.

root 원격 접속을 차단하는 이유는 관리자 권한 계정이 직접 외부 로그인 대상이 되는 위험을 줄이기 위해서입니다. 운영 환경에서는 일반 계정으로 접속한 뒤 필요한 경우에만 `sudo`를 사용하는 방식이 더 안전합니다.

### 3.2 방화벽과 최소 포트 허용

방화벽은 서버로 들어오는 네트워크 접근을 제어합니다. 이 과제에서는 SSH용 `20022/tcp`와 앱용 `15034/tcp`만 허용합니다.

필요한 포트만 열어 두면 사용하지 않는 서비스가 외부 공격면이 되는 위험을 줄일 수 있습니다.

### 3.3 계정, 그룹, 최소 권한

여러 사용자가 같은 서버를 사용할 때는 역할에 따라 계정과 그룹을 분리해야 합니다.

- `agent-admin`: 운영 및 cron 실행 계정
- `agent-dev`: 스크립트 작성 및 관리 계정
- `agent-test`: 테스트 계정
- `agent-common`: 공용 업로드 디렉토리 접근 그룹
- `agent-core`: 민감 디렉토리 접근 그룹

최소 권한 원칙은 각 사용자와 프로세스가 필요한 권한만 갖도록 제한하는 운영 원칙입니다.

### 3.4 디렉토리 권한과 ACL

`upload_files`는 공용 작업 공간이므로 `agent-common` 그룹에 읽기/쓰기 권한을 부여합니다.

`api_keys`와 `/var/log/agent-app`은 민감 정보와 운영 로그를 포함하므로 `agent-core` 그룹으로 접근을 제한합니다.

ACL은 Access Control List의 약자이며, 파일이나 디렉토리에 대해 추가적인 접근 권한 목록을 부여하는 기능입니다.

기본 Unix 권한은 소유자, 그룹, 기타 사용자 기준으로만 권한을 나눕니다.

```text
owner / group / others
```

하지만 실제 운영에서는 기본 그룹 하나만으로는 권한 정책을 표현하기 애매한 경우가 있습니다. 이때 ACL을 사용하면 특정 사용자나 특정 그룹에 대해 추가 권한을 더 세밀하게 부여할 수 있습니다.

ACL 권한은 `setfacl`로 설정하고, `getfacl`로 실제 적용 상태를 확인합니다.

디렉토리 권한에서 `x`는 파일 실행이 아니라 해당 디렉토리로 진입하거나 하위 경로로 통과할 수 있는 권한입니다. 따라서 상위 디렉토리에는 `--x`만 부여해 목록 조회는 막고, 특정 하위 디렉토리까지 도달만 허용할 수 있습니다.

이 과제에서는 `agent-test`가 `$AGENT_HOME/upload_files`에는 접근해야 하지만 `$AGENT_HOME/api_keys`에는 접근하면 안 됩니다. 그래서 부모 경로에는 `agent-common`의 통과 권한만 ACL로 추가하고, 실제 읽기/쓰기 권한은 `upload_files`에만 부여합니다.

### 3.5 환경 변수로 실행 환경 고정

환경 변수는 앱이 실행될 때 참조할 경로와 포트 값을 외부에서 주입하는 방식입니다.

이 과제에서는 `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR`을 사용해 앱 실행 환경을 명확히 고정합니다.

### 3.6 Health Check와 Warning 분리

프로세스 미실행이나 포트 미개방은 앱이 정상 서비스 상태가 아니므로 `monitor.sh`가 `exit 1`로 종료해야 합니다.

반면 방화벽 비활성, CPU/MEM/DISK 임계치 초과는 운영자가 확인해야 할 경고 상황이므로 `[WARNING]`을 출력하되 스크립트는 계속 진행합니다.

이렇게 분리하면 서비스 가용성에 직접 영향을 주는 장애와, 운영자가 추적해야 하는 위험 신호를 구분할 수 있습니다.

### 3.7 로그 누적과 리다이렉션

`>`는 파일을 새로 덮어쓰고, `>>`는 기존 파일 뒤에 내용을 추가합니다.

모니터링 로그는 시간 순서대로 누적되어야 하므로 `monitor.log` 기록에는 `>>`를 사용해야 합니다.

### 3.8 cron 자동 실행

cron은 정해진 시간 주기에 명령을 자동 실행하는 Linux 스케줄러입니다.

이 과제에서는 `agent-admin` 계정의 crontab에 `monitor.sh`를 매분 실행하도록 등록합니다.

cron은 비대화형 환경에서 실행되므로 스크립트 안에서는 필요한 경로를 명확히 지정해야 합니다. 상대 경로나 현재 쉘에만 설정된 환경 변수에 의존하면 수동 실행은 성공하지만 cron 실행은 실패할 수 있습니다.

### 3.9 로그 용량 관리

모니터링 로그는 계속 누적되므로 용량 관리가 필요합니다. 이 과제에서는 `monitor.log`가 커질 때 10MB/10개 기준으로 관리합니다.

구현 방식은 logrotate를 사용하거나, `monitor.sh` 내부에서 직접 회전 로직을 작성할 수 있습니다.

logrotate는 운영체제의 표준 로그 관리 방식이고, 스크립트 내부 회전 로직은 제출 파일만으로 동작을 설명하기 쉽다는 장점이 있습니다. 최종 구현에서는 선택한 방식과 이유를 기록합니다.

### 3.10 상태 확인 명령

프로세스 확인에는 `pgrep` 또는 `ps`를 사용할 수 있습니다. `pgrep`은 프로세스 이름이나 실행 인자를 기준으로 PID를 찾기 쉽고, `ps`는 더 자세한 프로세스 정보를 확인할 수 있습니다.

포트 확인에는 `ss` 또는 `netstat`를 사용할 수 있습니다. 최신 Linux 환경에서는 `ss`가 기본 도구로 더 적합하며, LISTEN 상태의 TCP 포트를 확인하는 데 사용합니다.

---

## 4. 수행 내역

### 4.1 계정 및 그룹 생성

#### 실행 명령

```bash
# 기존 계정 존재 여부 확인
getent passwd agent-admin
getent passwd agent-dev
getent passwd agent-test

# 기존 그룹 존재 여부 확인
getent group agent-common
getent group agent-core

sudo groupadd agent-common # 공용 접근 그룹 생성
sudo groupadd agent-core   # 핵심 운영 접근 그룹 생성

sudo useradd -m -s /bin/bash agent-admin # 운영/관리 계정 생성 및 홈 디렉토리 생성
sudo useradd -m -s /bin/bash agent-dev   # 개발/운영 계정 생성 및 홈 디렉토리 생성
sudo useradd -m -s /bin/bash agent-test  # QA/테스트 계정 생성 및 홈 디렉토리 생성

sudo usermod -aG agent-common,agent-core agent-admin # agent-admin을 공용 그룹과 핵심 운영 그룹에 추가
sudo usermod -aG agent-common,agent-core agent-dev   # agent-dev를 공용 그룹과 핵심 운영 그룹에 추가
sudo usermod -aG agent-common agent-test             # agent-test를 공용 그룹에만 추가

# 생성된 계정과 그룹 포함 관계 확인
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

#### 확인 결과

```text
uid=1000(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)
uid=1001(agent-dev) gid=1003(agent-dev) groups=1003(agent-dev),1000(agent-common),1001(agent-core)
uid=1002(agent-test) gid=1004(agent-test) groups=1004(agent-test),1000(agent-common)
agent-common:x:1000:agent-admin,agent-dev,agent-test
agent-core:x:1001:agent-admin,agent-dev
```

#### 정리

- 생성 계정: `agent-admin`, `agent-dev`, `agent-test`
- 생성 그룹: `agent-common`, `agent-core`
- `agent-common`에는 `agent-admin`, `agent-dev`, `agent-test`가 포함되었다.
- `agent-core`에는 `agent-admin`, `agent-dev`만 포함되었다.
- `agent-test`는 `agent-core`에 포함하지 않아 API 키와 운영 로그 같은 핵심 영역 접근 대상에서 제외했다.

### 4.2 디렉토리 구조 및 접근 권한 설정

#### 실행 명령

```bash
# Agent 앱 기준 디렉토리 생성
sudo mkdir -p /home/agent-admin/agent-app/bin
sudo mkdir -p /home/agent-admin/agent-app/upload_files
sudo mkdir -p /home/agent-admin/agent-app/api_keys
sudo mkdir -p /var/log/agent-app

sudo chown agent-admin:agent-core /home/agent-admin/agent-app # AGENT_HOME 소유자/그룹 설정
sudo chmod 750 /home/agent-admin/agent-app                   # 소유자는 rwx, agent-core는 r-x, others는 차단

sudo chown agent-dev:agent-core /home/agent-admin/agent-app/bin # monitor.sh 배치 디렉토리 소유자/그룹 설정
sudo chmod 750 /home/agent-admin/agent-app/bin                  # agent-core만 실행 가능하도록 제한

sudo chown agent-admin:agent-common /home/agent-admin/agent-app/upload_files # 공용 업로드 디렉토리 그룹 설정
sudo chmod 770 /home/agent-admin/agent-app/upload_files                     # agent-common에 읽기/쓰기 권한 부여

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys # API 키 디렉토리 그룹 설정
sudo chmod 770 /home/agent-admin/agent-app/api_keys                   # agent-core에만 읽기/쓰기 권한 부여

sudo chown agent-admin:agent-core /var/log/agent-app # Agent 로그 디렉토리 그룹 설정
sudo chmod 770 /var/log/agent-app                   # agent-core에만 읽기/쓰기 권한 부여

# agent-common이 upload_files까지 도달할 수 있도록 부모 디렉토리에 통과 권한만 부여
sudo setfacl -m g:agent-common:--x /home/agent-admin
sudo setfacl -m g:agent-common:--x /home/agent-admin/agent-app

# 디렉토리 권한 확인
sudo ls -ld /home
sudo ls -ld /home/agent-admin
sudo ls -ld /home/agent-admin/agent-app
sudo ls -ld /home/agent-admin/agent-app/bin
sudo ls -ld /home/agent-admin/agent-app/upload_files
sudo ls -ld /home/agent-admin/agent-app/api_keys
sudo ls -ld /var/log/agent-app

# ACL 적용 상태 확인
sudo getfacl /home/agent-admin
sudo getfacl /home/agent-admin/agent-app
sudo getfacl /home/agent-admin/agent-app/upload_files
sudo getfacl /home/agent-admin/agent-app/api_keys
sudo getfacl /var/log/agent-app

# agent-test 접근 정책 검증
sudo -u agent-test ls /home/agent-admin/agent-app/upload_files
sudo -u agent-test ls /home/agent-admin/agent-app/api_keys
```

#### 확인 결과

```text
drwxr-xr-x 1 root root 68 May 24 17:26 /home
drwxr-x--- 1 agent-admin agent-admin 72 May 24 18:00 /home/agent-admin
drwxr-x--- 1 agent-admin agent-core 46 May 24 18:00 /home/agent-admin/agent-app
drwxr-x--- 1 agent-dev agent-core 0 May 24 18:00 /home/agent-admin/agent-app/bin
drwxrwx--- 1 agent-admin agent-common 0 May 24 18:00 /home/agent-admin/agent-app/upload_files
drwxrwx--- 1 agent-admin agent-core 0 May 24 18:00 /home/agent-admin/agent-app/api_keys
drwxrwx--- 1 agent-admin agent-core 0 May 24 18:00 /var/log/agent-app

# file: home/agent-admin
# owner: agent-admin
# group: agent-admin
user::rwx
group::r-x
group:agent-common:--x
mask::r-x
other::---

# file: home/agent-admin/agent-app
# owner: agent-admin
# group: agent-core
user::rwx
group::r-x
group:agent-common:--x
mask::r-x
other::---

# file: home/agent-admin/agent-app/upload_files
# owner: agent-admin
# group: agent-common
user::rwx
group::rwx
other::---

# file: home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
user::rwx
group::rwx
other::---

# file: var/log/agent-app
# owner: agent-admin
# group: agent-core
user::rwx
group::rwx
other::---

ls: cannot open directory '/home/agent-admin/agent-app/api_keys': Permission denied
```

#### 정리

- `AGENT_HOME`: `/home/agent-admin/agent-app`
- `upload_files`: `agent-admin:agent-common`, `770`
- `api_keys`: `agent-admin:agent-core`, `770`
- `/var/log/agent-app`: `agent-admin:agent-core`, `770`
- `agent-common`에는 `$AGENT_HOME`까지 도달할 수 있도록 부모 디렉토리에 `--x` ACL만 부여했다.
- `agent-test`는 `upload_files`에는 접근 가능하지만 `api_keys`에는 접근할 수 없다.

### 4.3 앱 실행 환경

#### 실행 명령

```bash
# Agent 앱 실행에 필요한 환경 변수 파일 생성
sudo -u agent-admin tee /home/agent-admin/agent-app/.env > /dev/null <<'EOF'
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
export AGENT_LOG_DIR=/var/log/agent-app
EOF

# 앱이 검증할 API 키 파일 생성
echo 'agent_api_key_test' | sudo tee /home/agent-admin/agent-app/api_keys/secret.key > /dev/null

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/.env             # 환경 변수 파일 소유자/그룹 설정
sudo chmod 640 /home/agent-admin/agent-app/.env                                # 소유자는 읽기/쓰기, agent-core는 읽기만 허용

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/secret.key # 키 파일 소유자/그룹 설정
sudo chmod 640 /home/agent-admin/agent-app/api_keys/secret.key                    # 소유자는 읽기/쓰기, agent-core는 읽기만 허용

# 환경 변수와 키 파일 권한 확인
sudo ls -l /home/agent-admin/agent-app/.env
sudo ls -l /home/agent-admin/agent-app/api_keys/secret.key

# agent-admin 기준 환경 변수 로드 확인
sudo -u agent-admin bash -lc 'source /home/agent-admin/agent-app/.env && env | grep "^AGENT_" | sort'

# agent-admin은 키 파일을 읽을 수 있어야 함
sudo -u agent-admin cat /home/agent-admin/agent-app/api_keys/secret.key

# agent-test는 키 파일을 읽을 수 없어야 함
sudo -u agent-test cat /home/agent-admin/agent-app/api_keys/secret.key
```

#### 확인 결과

```text
-rw-r----- 1 agent-admin agent-core 235 May 24 18:30 /home/agent-admin/agent-app/.env
-rw-r----- 1 agent-admin agent-core 19 May 24 18:30 /home/agent-admin/agent-app/api_keys/secret.key
AGENT_HOME=/home/agent-admin/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
agent_api_key_test
cat: /home/agent-admin/agent-app/api_keys/secret.key: Permission denied
```

#### 정리

- 실행 계정: `agent-admin`
- 환경 변수 파일: `/home/agent-admin/agent-app/.env`
- 키 파일: `/home/agent-admin/agent-app/api_keys/secret.key`
- `.env`와 키 파일은 `agent-admin:agent-core`, `640`으로 설정했다.
- `agent-admin`은 키 파일을 읽을 수 있고, `agent-test`는 키 파일을 읽을 수 없다.

### 4.4 앱 실행 확인

#### 실행 명령

```bash
# ARM64 앱 바이너리를 AGENT_HOME에 복사
sudo cp /mnt/mac/Users/hyun/Desktop/dev/cdsy/b1-1/agent-app/agent-app-linux-arm64 /home/agent-admin/agent-app/agent-app-linux-arm64

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/agent-app-linux-arm64 # 앱 바이너리 소유자/그룹 설정
sudo chmod 750 /home/agent-admin/agent-app/agent-app-linux-arm64                   # agent-admin과 agent-core만 실행 가능하도록 설정

# 앱 바이너리 권한과 실행 가능 여부 확인
sudo ls -l /home/agent-admin/agent-app/agent-app-linux-arm64
sudo -u agent-admin test -x /home/agent-admin/agent-app/agent-app-linux-arm64 && echo "executable"

# agent-admin 계정으로 환경 변수를 로드한 뒤 앱 실행
sudo -u agent-admin bash -lc 'source /home/agent-admin/agent-app/.env && /home/agent-admin/agent-app/agent-app-linux-arm64'

# 다른 터미널에서 포트 LISTEN 상태 확인
sudo ss -tulnp | grep 15034
```

#### 확인 결과

```text
-rwxr-x--- 1 agent-admin agent-core 7537848 May 24 18:28 /home/agent-admin/agent-app/agent-app-linux-arm64
executable

>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1000)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-05-24 18:31:14,945 [INFO] Agent listening at port 15034

tcp   LISTEN 0      1                   0.0.0.0:15034      0.0.0.0:*    users:(("agent-app-linux",pid=3800,fd=4))
```

#### 정리

- 앱은 `agent-admin` 계정으로 실행했다.
- Boot Sequence 5단계가 모두 `[OK]`로 통과했다.
- `Agent READY`가 출력되었다.
- `0.0.0.0:15034`에서 LISTEN 상태임을 확인했다.

### 4.5 SSH 설정

#### 실행 명령

```bash
# sshd 설정 파일 생성
sudo tee /etc/ssh/sshd_config.d/agent-hardening.conf > /dev/null <<'EOF'
Port 20022
PermitRootLogin no
EOF

# sshd 런타임 디렉토리 생성 및 설정 문법 검사
sudo mkdir -p /run/sshd
sudo sshd -t

# Ubuntu 24.04 ssh.socket의 ListenStream을 20022로 재정의
sudo mkdir -p /etc/systemd/system/ssh.socket.d
sudo tee /etc/systemd/system/ssh.socket.d/listen.conf > /dev/null <<'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:20022
ListenStream=[::]:20022
EOF

# systemd 설정 재로드 및 SSH socket/service 재시작
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh

# 설정 파일과 socket 설정 확인
sudo grep -R "Port\|PermitRootLogin" /etc/ssh/sshd_config /etc/ssh/sshd_config.d
sudo systemctl cat --no-pager ssh.socket

# 실제 LISTEN 포트 확인
sudo ss -tulnp | grep 20022
sudo ss -tulnp | grep ':22 '
```

#### 확인 결과

```text
/etc/ssh/sshd_config:#Port 22
/etc/ssh/sshd_config:#PermitRootLogin prohibit-password
/etc/ssh/sshd_config.d/agent-hardening.conf:Port 20022
/etc/ssh/sshd_config.d/agent-hardening.conf:PermitRootLogin no

# /run/systemd/generator/ssh.socket.d/addresses.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:20022
ListenStream=[::]:20022

# /etc/systemd/system/ssh.socket.d/listen.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:20022
ListenStream=[::]:20022

tcp   LISTEN 0      4096                0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=3986,fd=3),("systemd",pid=1,fd=51))
tcp   LISTEN 0      4096                   [::]:20022         [::]:*    users:(("sshd",pid=3986,fd=4),("systemd",pid=1,fd=52))

sudo ss -tulnp | grep ':22 ' -> 출력 없음
```

#### 정리

- SSH 포트를 `20022`로 변경했다.
- root 원격 접속을 `PermitRootLogin no`로 차단했다.
- `ssh.socket`의 `ListenStream`도 `20022`로 재정의했다.
- `ss` 결과에서 `0.0.0.0:20022`, `[::]:20022` LISTEN 상태를 확인했다.
- 기존 `22` 포트는 LISTEN 결과에 나타나지 않았다.

### 4.6 방화벽 설정

#### 실행 명령

```bash
sudo ufw --force reset              # 기존 UFW 규칙 초기화

sudo ufw default deny incoming      # 인바운드 기본 차단
sudo ufw default allow outgoing     # 아웃바운드 기본 허용

sudo ufw allow 20022/tcp            # SSH 접속 포트 허용
sudo ufw allow 15034/tcp            # Agent 앱 포트 허용

sudo ufw --force enable             # UFW 활성화

sudo ufw status verbose             # 방화벽 상태와 허용 규칙 확인
```

#### 확인 결과

```text
Default incoming policy changed to 'deny'
Default outgoing policy changed to 'allow'
Rules updated
Rules updated (v6)
Rules updated
Rules updated (v6)
Firewall is active and enabled on system startup

Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
20022/tcp (v6)             ALLOW IN    Anywhere (v6)
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

#### 정리

- 선택 도구: UFW
- 기본 정책: 인바운드 차단, 아웃바운드 허용
- 허용 포트: `20022/tcp`, `15034/tcp`
- 활성화 상태: `active`

### 4.7 monitor.sh

#### 실행 명령

```bash
# 로컬 레포의 monitor.sh를 실습 서버의 실행 위치로 배치하면서 소유자/그룹/권한까지 설정
sudo install -o agent-dev -g agent-core -m 750 /mnt/mac/Users/hyun/Desktop/dev/cdsy/b1-1/bin/monitor.sh /home/agent-admin/agent-app/bin/monitor.sh

sudo ls -l /home/agent-admin/agent-app/bin/monitor.sh # monitor.sh 파일 권한 확인

sudo -u agent-admin bash -n /home/agent-admin/agent-app/bin/monitor.sh # Bash 문법 검사

sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh # agent-admin 계정으로 monitor.sh 실행

sudo -u agent-admin env APP_PATTERN=__not_running__ /home/agent-admin/agent-app/bin/monitor.sh # 프로세스 비정상 상황 테스트
echo $? # 직전 명령의 종료 코드 확인

sudo -u agent-admin env APP_PORT=1 /home/agent-admin/agent-app/bin/monitor.sh # 포트 비정상 상황 테스트
echo $? # 직전 명령의 종료 코드 확인

sudo -u agent-admin env CPU_THRESHOLD=0 MEM_THRESHOLD=0 DISK_THRESHOLD=0 /home/agent-admin/agent-app/bin/monitor.sh # 임계값 경고 상황 테스트
echo $? # 직전 명령의 종료 코드 확인

sudo tail -n 5 /var/log/agent-app/monitor.log # 로그 누적 확인
```

#### 확인 결과

```text
-rwxr-x--- 1 agent-dev agent-core 5233 May 24 19:37 /home/agent-admin/agent-app/bin/monitor.sh

bash -n 문법 검사: 출력 없음

====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app-linux-arm64'... [OK] (PID: 3798)
Checking port 15034... [OK]
Checking firewall... [OK] (UFW enabled)

[RESOURCE MONITORING]
CPU Usage : 0.1%
MEM Usage : 4.4%
DISK Used : 1%


[INFO] Log appended: /var/log/agent-app/monitor.log

[2026-05-24 19:40:01] PID:3798 CPU:1.2% MEM:4.9% DISK_USED:1%
[2026-05-24 19:40:02] PID:3798 CPU:1.4% MEM:4.9% DISK_USED:1%
[2026-05-24 19:43:11] PID:3798 CPU:0.2% MEM:4.3% DISK_USED:1%
[2026-05-24 19:43:48] PID:3798 CPU:0.2% MEM:5.0% DISK_USED:1%
[2026-05-24 19:56:07] PID:3798 CPU:0.1% MEM:4.4% DISK_USED:1%

====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '__not_running__'... [FAIL]
[ERROR] Agent process is not running.
1

====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app-linux-arm64'... [OK] (PID: 3798)
Checking port 1... [FAIL]
[ERROR] TCP port 1 is not in LISTEN state.
1

====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app-linux-arm64'... [OK] (PID: 3798)
Checking port 15034... [OK]
Checking firewall... [OK] (UFW enabled)

[RESOURCE MONITORING]
CPU Usage : 0.0%
MEM Usage : 4.0%
DISK Used : 1%

[WARNING] MEM threshold exceeded (4.0% > 0%)
[WARNING] DISK threshold exceeded (1% > 0%)

[INFO] Log appended: /var/log/agent-app/monitor.log
0
```

#### 정리

- 경로: `/home/agent-admin/agent-app/bin/monitor.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `750`
- 실행 계정: `agent-admin`
- 프로세스 점검: `ps -eo pid=,comm=,args=`로 대상 앱 PID를 찾고, 미실행 시 `exit 1`로 종료한다.
- 포트 점검: `ss -H -tuln`으로 TCP LISTEN 포트를 확인하고, `15034` 미개방 시 `exit 1`로 종료한다.
- 방화벽 점검: `ufw status`를 우선 확인하고, 일반 계정에서 권한 제한이 있으면 `/etc/ufw/ufw.conf`의 `ENABLED=yes`를 보조 확인값으로 사용한다.
- CPU 사용률: `/proc/stat`의 전체 CPU 값을 1초 간격으로 두 번 읽고, idle/total 차이를 계산한다.
- 메모리 사용률: `/proc/meminfo`의 `MemTotal`, `MemAvailable`을 기준으로 계산한다.
- 디스크 사용률: `df -P /`로 루트 파티션의 Used %를 수집한다.
- 경고 조건: CPU `20%`, MEM `10%`, DISK `80%` 초과 시 `[WARNING]`을 출력하되 종료하지 않는다.
- 로그 기록: `/var/log/agent-app/monitor.log`에 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%` 형식으로 `>>` 누적 기록한다.
- 로그 용량 관리: `monitor.log`가 `10MB` 이상이면 `.1`부터 `.10`까지 회전시키고, 가장 오래된 `.10` 파일은 삭제한다.
- `monitor.sh`는 실행될 때마다 로그를 1줄 기록한다. 과제의 “매분 자동 기록” 요구사항은 다음 단계에서 `cron`이 매분 이 스크립트를 실행하도록 등록해 충족한다.

#### 코드 설명

`monitor.sh`는 크게 설정값 정의, Health Check, 리소스 수집, 경고 출력, 로그 기록, 로그 회전 순서로 동작한다.

| 구간 | 코드 요소 | 설명 |
|---|---|---|
| 기본 설정 | `set -euo pipefail` | 명령 실패, 미정의 변수 사용, 파이프라인 실패를 엄격하게 처리해 스크립트 오류를 빨리 발견한다. |
| 기본 설정 | `APP_PATTERN`, `APP_PORT`, `LOG_DIR` | 모니터링 대상 프로세스명, 포트, 로그 경로를 변수로 분리했다. 기본값은 과제 기준에 맞추고, 테스트할 때는 환경 변수로 덮어쓸 수 있게 했다. |
| 기본 설정 | `CPU_THRESHOLD`, `MEM_THRESHOLD`, `DISK_THRESHOLD` | CPU, 메모리, 디스크 경고 기준을 변수로 분리했다. 과제 기준은 각각 `20`, `10`, `80`이다. |
| 기본 설정 | `MAX_LOG_BYTES`, `MAX_LOG_FILES` | 로그 회전 기준을 `10MB`, `10개`로 관리하기 위한 값이다. |
| 기본 설정 | `umask 007` | 새로 생성되는 로그 파일이 기본적으로 others 권한을 갖지 않도록 제한한다. |
| 프로세스 확인 | `find_agent_pid` | `ps -eo pid=,comm=,args=`로 실행 중인 프로세스를 조회하고, `agent-app-linux-arm64`에 해당하는 PID를 찾는다. |
| 프로세스 확인 | `check_process` | PID가 없으면 `[FAIL]`을 출력하고 `exit 1`로 종료한다. 프로세스가 없으면 앱이 실행 중이 아니므로 Health Check 실패로 본다. |
| 포트 확인 | `check_port` | `ss -H -tuln`으로 TCP LISTEN 포트를 조회하고, 로컬 주소의 마지막 포트 번호가 `15034`인지 정확히 비교한다. |
| 방화벽 확인 | `check_firewall` | `ufw status`로 활성화 여부를 확인한다. 일반 계정에서 권한 제한이 있으면 `/etc/ufw/ufw.conf`의 `ENABLED=yes`를 보조 확인값으로 사용한다. |
| CPU 수집 | `read_cpu_times`, `get_cpu_usage` | `/proc/stat`의 전체 CPU 누적값을 1초 간격으로 두 번 읽고, idle/total 차이를 이용해 CPU 사용률을 계산한다. |
| 메모리 수집 | `get_mem_usage` | `/proc/meminfo`의 `MemTotal`, `MemAvailable` 값을 이용해 현재 메모리 사용률을 계산한다. |
| 디스크 수집 | `get_disk_usage` | `df -P /`로 루트 파티션의 사용률을 가져오고 `%` 기호를 제거한다. |
| 경고 처리 | `float_gt`, `warn_if_needed` | CPU/MEM/DISK 값이 임계값을 초과하면 `[WARNING]`을 출력한다. 경고는 운영자가 확인해야 할 상태이므로 스크립트를 종료하지 않는다. |
| 로그 준비 | `prepare_log_file` | 로그 디렉토리 존재 여부와 쓰기 권한을 확인하고, `monitor.log` 파일을 준비한다. |
| 로그 회전 | `rotate_logs` | `monitor.log`가 기준 크기 이상이면 기존 파일을 `.1`, `.2`처럼 뒤로 밀고, 가장 오래된 `.10` 파일을 삭제한다. |
| 로그 기록 | `append_log` | 현재 시각, PID, CPU, MEM, DISK 값을 지정 포맷으로 `monitor.log`에 누적 기록한다. |
| 실행 흐름 | `main` | Health Check를 먼저 수행하고, 통과한 경우에만 리소스 수집, 경고 출력, 로그 회전, 로그 기록을 순서대로 실행한다. |

프로세스 확인에서 `pgrep -f`만 단순 사용하지 않은 이유는 테스트용 환경 변수나 `monitor.sh` 실행 명령 자체가 검색 결과에 잡힐 수 있기 때문이다. 그래서 `ps` 결과에서 `monitor.sh`, `sudo`, `bash`, `sh`, `env`, `awk` 같은 실행 보조 프로세스를 제외하고 실제 앱 프로세스를 우선 찾도록 했다.

포트 확인에서는 문자열 포함 여부만 보면 `APP_PORT=1`이 `15034` 안의 `1`과 잘못 매칭될 수 있다. 그래서 `ss` 출력의 로컬 주소에서 마지막 포트 번호만 분리한 뒤 정확히 같은지 비교했다.

전체 실행 흐름은 다음과 같다.

```text
monitor.sh 실행
-> Agent 프로세스 확인
   -> 실패 시 exit 1
-> TCP 15034 LISTEN 확인
   -> 실패 시 exit 1
-> 방화벽 활성화 확인
   -> 비활성 또는 확인 불가 시 WARNING만 출력
-> CPU/MEM/DISK 사용률 수집
-> 임계값 초과 여부 확인
   -> 초과 시 WARNING만 출력
-> monitor.log 용량 확인 및 회전
-> monitor.log에 현재 상태 누적 기록
```

### 4.8 cron 자동 실행

#### 실행 명령

```bash
systemctl is-active cron  # cron 서비스 실행 상태 확인
systemctl is-enabled cron # cron 서비스 부팅 자동 시작 여부 확인

sudo crontab -u agent-admin -l # agent-admin의 기존 crontab 확인

# 기존 monitor.sh 등록 줄은 제거하고, 매분 실행 cron 규칙을 등록
sudo bash -c '(crontab -u agent-admin -l 2>/dev/null | grep -v "/home/agent-admin/agent-app/bin/monitor.sh"; echo "* * * * * /home/agent-admin/agent-app/bin/monitor.sh >/dev/null 2>&1") | crontab -u agent-admin -'

sudo crontab -u agent-admin -l # agent-admin crontab 등록 확인

sudo wc -l /var/log/agent-app/monitor.log       # cron 실행 전 monitor.log 줄 수 확인
sudo tail -n 3 /var/log/agent-app/monitor.log   # cron 실행 전 최근 로그 확인

sleep 70 # cron이 최소 1번 이상 실행될 수 있도록 70초 대기

sudo wc -l /var/log/agent-app/monitor.log       # cron 실행 후 monitor.log 줄 수 확인
sudo tail -n 5 /var/log/agent-app/monitor.log   # cron 실행 후 최근 로그 확인
```

#### 확인 결과

```text
active
enabled

no crontab for agent-admin

* * * * * /home/agent-admin/agent-app/bin/monitor.sh >/dev/null 2>&1

16 /var/log/agent-app/monitor.log
[2026-05-24 19:43:48] PID:3798 CPU:0.2% MEM:5.0% DISK_USED:1%
[2026-05-24 19:56:07] PID:3798 CPU:0.1% MEM:4.4% DISK_USED:1%
[2026-05-24 19:56:42] PID:3798 CPU:0.0% MEM:4.0% DISK_USED:1%

20 /var/log/agent-app/monitor.log
[2026-05-24 19:56:42] PID:3798 CPU:0.0% MEM:4.0% DISK_USED:1%
[2026-05-24 20:08:02] PID:3798 CPU:0.1% MEM:4.4% DISK_USED:1%
[2026-05-24 20:09:02] PID:3798 CPU:0.3% MEM:4.8% DISK_USED:1%
[2026-05-24 20:10:02] PID:3798 CPU:0.0% MEM:4.0% DISK_USED:1%
[2026-05-24 20:11:02] PID:3798 CPU:0.0% MEM:4.9% DISK_USED:1%
```

#### 정리

- 실행 계정: `agent-admin`
- 등록 주기: 매분 실행 (`* * * * *`)
- 실행 명령: `/home/agent-admin/agent-app/bin/monitor.sh`
- 출력 처리: `>/dev/null 2>&1`로 cron 실행 출력은 버리고, 상태 기록은 `monitor.sh` 내부에서 `/var/log/agent-app/monitor.log`에 남긴다.
- 로그 증가 확인: `monitor.log` 줄 수가 `16`에서 `20`으로 증가했다.
- 자동 실행 확인: `20:08:02`, `20:09:02`, `20:10:02`, `20:11:02`처럼 1분 간격으로 로그가 누적되었다.

---

## 5. 장애 상황 대응

### 5.1 모니터링 대상이 Nginx로 바뀌는 경우

현재 `monitor.sh`는 제공 Agent 앱을 기준으로 작성되어 있다.
대상이 Nginx 같은 웹 서버로 바뀌면 핵심적으로 바꿔야 할 부분은 프로세스, 포트, 로그 경로, 방화벽 규칙이다.

| 변경 대상 | Agent 기준 | Nginx 예시 | 설명 |
|---|---|---|---|
| 프로세스 식별값 | `agent-app-linux-arm64` | `nginx` | `APP_PATTERN` 값을 바꿔야 프로세스 Health Check가 올바르게 동작한다. |
| 서비스 포트 | `15034` | `80` 또는 `443` | `APP_PORT` 값을 서비스 포트에 맞춰야 LISTEN 상태를 확인할 수 있다. |
| 방화벽 허용 포트 | `15034/tcp` | `80/tcp`, `443/tcp` | 실제 서비스 포트가 바뀌면 UFW 허용 규칙도 함께 바꿔야 한다. |
| 로그 경로 | `/var/log/agent-app/monitor.log` | `/var/log/nginx/*` 또는 별도 모니터링 로그 | 앱 로그와 모니터링 로그의 위치를 구분해서 관리해야 한다. |
| 실행 계정/권한 | `agent-admin`, `agent-core` | `www-data`, 운영 그룹 등 | 로그 디렉토리와 스크립트 실행 권한을 새 서비스 운영 계정 기준으로 재검토해야 한다. |

예를 들어 Nginx의 `80/tcp`를 감시한다면 실행 시 다음처럼 대상값을 바꿀 수 있다.

```bash
APP_PATTERN=nginx APP_PORT=80 /home/agent-admin/agent-app/bin/monitor.sh
```

다만 실제 운영에서는 매번 환경 변수를 붙이기보다 스크립트 상단 기본값이나 별도 환경 파일을 서비스 기준으로 고정하는 편이 관리하기 쉽다.

### 5.2 프로세스는 살아있지만 포트가 열리지 않은 경우

프로세스가 존재하는데 포트가 LISTEN 상태가 아니라면, 앱 프로세스 자체는 떠 있지만 네트워크 서비스 초기화에 실패했을 가능성이 있다.

주요 원인 후보는 다음과 같다.

- 앱 설정의 포트 값이 잘못되었다.
- 앱이 포트 바인딩 전에 오류가 발생했다.
- 이미 다른 프로세스가 같은 포트를 사용 중이다.
- 앱이 `127.0.0.1`에만 바인딩되어 외부 접근이 불가능하다.
- 방화벽은 열려 있지만 실제 서비스가 LISTEN 상태가 아니다.
- 실행 계정에 로그/키/디렉토리 접근 권한이 없어 앱 초기화가 중간에 실패했다.

확인 순서는 다음과 같이 진행한다.

```bash
ps -ef | grep agent-app-linux-arm64 # 앱 프로세스 존재 여부 확인
ss -tulnp | grep 15034              # 15034 포트 LISTEN 여부와 점유 프로세스 확인
sudo tail -n 50 /var/log/agent-app/agent_app.log # 앱 내부 오류 로그 확인
sudo ufw status verbose             # 방화벽 허용 규칙 확인
sudo ls -ld /home/agent-admin/agent-app /var/log/agent-app # 실행에 필요한 디렉토리 권한 확인
```

판단 기준은 다음과 같다.

- `ps`에는 보이지만 `ss`에 포트가 없으면 앱이 네트워크 리스닝까지 도달하지 못한 상태다.
- `ss`에 다른 PID가 같은 포트를 사용 중이면 포트 충돌이다.
- 앱 로그에 키 파일, 환경 변수, 권한 오류가 있으면 실행 환경 문제다.
- `127.0.0.1:15034`만 보이고 `0.0.0.0:15034`가 아니면 외부 접근 범위 설정을 확인해야 한다.

이 경우 무조건 재시작하기보다, 먼저 로그와 포트 점유 상태를 확인해 원인을 좁힌 뒤 수정하는 것이 좋다.

### 5.3 로그 급증으로 디스크가 가득 찰 위험이 있는 경우

로그가 급격히 증가하면 서비스 자체보다 디스크 고갈이 먼저 장애를 만들 수 있다.
디스크가 가득 차면 새 로그를 쓰지 못하고, 앱이 임시 파일이나 상태 파일을 만들지 못해 추가 장애로 이어질 수 있다.

단기 대응은 현재 디스크 사용량을 낮추는 데 집중한다.

```bash
df -h /var/log/agent-app             # 로그 디렉토리가 위치한 파일시스템 사용률 확인
sudo du -sh /var/log/agent-app/*     # 어떤 로그 파일이 큰지 확인
sudo tail -n 100 /var/log/agent-app/monitor.log # 최근 로그 패턴 확인
```

단기 조치 예시는 다음과 같다.

- 불필요한 오래된 로그를 압축하거나 삭제한다.
- `monitor.log` 회전이 정상 동작하는지 확인한다.
- 장애 분석에 필요한 최근 로그는 남기고, 오래된 대용량 로그부터 정리한다.
- 로그가 계속 폭증하면 앱 로그 레벨이나 반복 오류 원인을 먼저 확인한다.

중기 대응은 같은 문제가 반복되지 않도록 정책을 고정하는 것이다.

- `logrotate` 또는 스크립트 회전 로직으로 크기 기반 보존 정책을 적용한다.
- 보관 개수와 보관 기간을 정한다.
- DEBUG처럼 과도한 로그 레벨을 운영 환경에서 사용하지 않도록 조정한다.
- `/var/log`를 별도 파티션으로 분리하거나 외부 로그 수집 시스템으로 전송한다.
- 로그 증가량을 모니터링해 디스크 사용률이 일정 기준을 넘으면 경고하도록 한다.

이 과제에서는 `monitor.sh` 내부에서 `monitor.log`를 `10MB/10개` 기준으로 회전시켜, 모니터링 로그가 무제한 증가하지 않도록 했다.

---

## 6. 보너스 과제

### 6.1 report.sh 요약 리포트

`report.sh`는 `/var/log/agent-app/monitor.log`를 분석해 CPU, Memory, Disk 사용률의 평균, 최대, 최소와 샘플 수를 출력하는 보너스 스크립트다.

#### 실행 명령

```bash
# 로컬 레포의 report.sh를 실습 서버의 실행 위치로 배치하면서 소유자/그룹/권한까지 설정
sudo install -o agent-dev -g agent-core -m 750 /mnt/mac/Users/hyun/Desktop/dev/cdsy/b1-1/bin/report.sh /home/agent-admin/agent-app/bin/report.sh

sudo ls -l /home/agent-admin/agent-app/bin/report.sh # report.sh 파일 권한 확인

sudo -u agent-admin bash -n /home/agent-admin/agent-app/bin/report.sh # Bash 문법 검사

sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh # 전체 monitor.log 기준 리포트 생성

sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh --start '2026-05-24 20:08:00' --end '2026-05-24 20:11:59' # 특정 시간 구간 리포트 생성
```

#### 확인 결과

```text
-rwxr-x--- 1 agent-dev agent-core 3018 May 24 20:34 /home/agent-admin/agent-app/bin/report.sh

bash -n 문법 검사: 출력 없음

====== STATISTICS REPORT ======
[CPU]
Average : 0.7%
Maximum : 4.1% at 2026-05-24 20:31:02
Minimum : 0.0% at 2026-05-24 19:56:42
[Memory]
Average : 4.5%
Maximum : 5.2% at 2026-05-24 20:16:03
Minimum : 3.3% at 2026-05-24 20:22:02
[Disk]
Average : 1.0%
Maximum : 1.0% at 2026-05-24 19:35:53
Minimum : 1.0% at 2026-05-24 19:35:53
[Samples]
Data Points: 44 samples

====== STATISTICS REPORT ======
[CPU]
Average : 0.1%
Maximum : 0.3% at 2026-05-24 20:09:02
Minimum : 0.0% at 2026-05-24 20:10:02
[Memory]
Average : 4.5%
Maximum : 4.9% at 2026-05-24 20:11:02
Minimum : 4.0% at 2026-05-24 20:10:02
[Disk]
Average : 1.0%
Maximum : 1.0% at 2026-05-24 20:08:02
Minimum : 1.0% at 2026-05-24 20:08:02
[Samples]
Data Points: 4 samples
```

#### 정리

- 경로: `/home/agent-admin/agent-app/bin/report.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `750`
- 실행 계정: `agent-admin`
- 기본 로그 파일: `/var/log/agent-app/monitor.log`
- 출력 항목: CPU/MEM/DISK의 평균, 최대, 최소, 샘플 수
- 시간 필터: `--start`, `--end` 옵션으로 특정 구간의 로그만 분석할 수 있다.
- 구현 방식: `awk`로 `monitor.log`의 `CPU:`, `MEM:`, `DISK_USED:` 값을 파싱하고 누적합, 최대값, 최소값을 계산한다.

### 6.2 시간 기반 로그 보존 정책

`archive_logs.sh`는 `/var/log/agent-app/*.log` 중 7일 이상 지난 로그를 압축해 `/var/log/monitor/agent-app/archive/`로 이동하고, 30일 이상 지난 `.gz` 아카이브를 삭제하는 보너스 스크립트다.

#### 실행 명령

```bash
# 로컬 레포의 archive_logs.sh를 실습 서버의 실행 위치로 배치하면서 소유자/그룹/권한까지 설정
sudo install -o agent-dev -g agent-core -m 750 /mnt/mac/Users/hyun/Desktop/dev/cdsy/b1-1/bin/archive_logs.sh /home/agent-admin/agent-app/bin/archive_logs.sh

sudo ls -l /home/agent-admin/agent-app/bin/archive_logs.sh # archive_logs.sh 파일 권한 확인

sudo -u agent-admin bash -n /home/agent-admin/agent-app/bin/archive_logs.sh # Bash 문법 검사

sudo mkdir -p /var/log/monitor/agent-app/archive # 아카이브 디렉토리 생성
sudo chown agent-admin:agent-core /var/log/monitor/agent-app/archive # 아카이브 디렉토리 소유자/그룹 설정
sudo chmod 770 /var/log/monitor/agent-app/archive # agent-core 그룹에 읽기/쓰기/진입 권한 부여

sudo ls -ld /var/log/monitor/agent-app/archive # 아카이브 디렉토리 권한 확인

sudo -u agent-admin /home/agent-admin/agent-app/bin/archive_logs.sh # 기본 경로 기준 로그 보존 정책 실행
```

임시 디렉토리 검증 명령은 실제 운영 로그를 건드리지 않기 위해 `/tmp` 아래 테스트 로그를 만들어 실행했다.

```bash
sudo -u agent-admin bash -lc 'set -euo pipefail; tmp=$(mktemp -d); logdir="$tmp/logs"; archivedir="$tmp/archive"; mkdir -p "$logdir" "$archivedir"; printf "old log\n" > "$logdir/old.log"; printf "new log\n" > "$logdir/new.log"; touch -d "8 days ago" "$logdir/old.log"; touch -d "1 day ago" "$logdir/new.log"; printf "expired archive\n" | gzip > "$archivedir/expired.log.gz"; printf "fresh archive\n" | gzip > "$archivedir/fresh.log.gz"; touch -d "31 days ago" "$archivedir/expired.log.gz"; touch -d "1 day ago" "$archivedir/fresh.log.gz"; /home/agent-admin/agent-app/bin/archive_logs.sh --log-dir "$logdir" --archive-dir "$archivedir" --compress-days 7 --delete-days 30; echo "TMP_DIR:$tmp"; find "$tmp" -maxdepth 3 -type f -printf "%P\n" | sort'

sudo -u agent-admin bash -lc 'set -euo pipefail; tmp=$(mktemp -d); mkdir -p "$tmp/logs" "$tmp/archive"; /home/agent-admin/agent-app/bin/archive_logs.sh --log-dir "$tmp/logs" --archive-dir "$tmp/archive" --compress-days 7 --delete-days 30'
```

#### 확인 결과

```text
-rwxr-x--- 1 agent-dev agent-core 4156 May 24 20:57 /home/agent-admin/agent-app/bin/archive_logs.sh

bash -n 문법 검사: 출력 없음

drwxrwx--- 1 agent-admin agent-core 0 May 24 20:58 /var/log/monitor/agent-app/archive

====== LOG ARCHIVE RESULT ======
Log directory     : /var/log/agent-app
Archive directory : /var/log/monitor/agent-app/archive
Compress policy   : *.log older than 7 days
Delete policy     : *.gz older than 30 days

[INFO] No *.log files older than 7 days in /var/log/agent-app.
[INFO] No archived *.gz files older than 30 days in /var/log/monitor/agent-app/archive.

====== LOG ARCHIVE RESULT ======
Log directory     : /tmp/tmp.exhb3nWY3V/logs
Archive directory : /tmp/tmp.exhb3nWY3V/archive
Compress policy   : *.log older than 7 days
Delete policy     : *.gz older than 30 days

[INFO] Archived: /tmp/tmp.exhb3nWY3V/logs/old.log -> /tmp/tmp.exhb3nWY3V/archive/old.log.20260524213329.7621.gz
[INFO] Deleted old archive: /tmp/tmp.exhb3nWY3V/archive/expired.log.gz
TMP_DIR:/tmp/tmp.exhb3nWY3V
archive/fresh.log.gz
archive/old.log.20260524213329.7621.gz
logs/new.log

====== LOG ARCHIVE RESULT ======
Log directory     : /tmp/tmp.awx4rxNNCa/logs
Archive directory : /tmp/tmp.awx4rxNNCa/archive
Compress policy   : *.log older than 7 days
Delete policy     : *.gz older than 30 days

[INFO] No *.log files older than 7 days in /tmp/tmp.awx4rxNNCa/logs.
[INFO] No archived *.gz files older than 30 days in /tmp/tmp.awx4rxNNCa/archive.
```

#### 정리

- 경로: `/home/agent-admin/agent-app/bin/archive_logs.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `750`
- 실행 계정: `agent-admin`
- 압축 대상: `/var/log/agent-app/*.log` 중 7일 이상 지난 파일
- 아카이브 경로: `/var/log/monitor/agent-app/archive/`
- 삭제 대상: archive 디렉토리의 `.gz` 중 30일 이상 지난 파일
- 예외 처리: 로그 디렉토리 미존재, 아카이브 디렉토리 미존재, 대상 파일 0개 상황에서 메시지를 출력하고 안전하게 종료한다.
- 검증 결과: 8일 지난 `old.log`는 `.gz`로 압축되어 archive로 이동했고, 31일 지난 `expired.log.gz`는 삭제되었다. 1일 지난 `new.log`와 `fresh.log.gz`는 유지되었다.

---

## 7. 트러블슈팅

### 7.1 디렉토리 권한 확인 중 Permission denied 발생

#### 증상

`hyun` 계정으로 `$AGENT_HOME` 하위 디렉토리 권한을 확인할 때 `Permission denied`가 발생했다.

```bash
ls -ld /home/agent-admin/agent-app
ls -ld /home/agent-admin/agent-app/bin
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys

getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
```

```text
ls: cannot access '/home/agent-admin/agent-app': Permission denied
ls: cannot access '/home/agent-admin/agent-app/bin': Permission denied
ls: cannot access '/home/agent-admin/agent-app/upload_files': Permission denied
ls: cannot access '/home/agent-admin/agent-app/api_keys': Permission denied
getfacl: /home/agent-admin/agent-app/upload_files: Permission denied
getfacl: /home/agent-admin/agent-app/api_keys: Permission denied
```

#### 원인

`/home/agent-admin/agent-app`를 `agent-admin:agent-core`, `750`으로 설정했기 때문에 `agent-core` 그룹에 속하지 않은 `hyun` 계정은 해당 디렉토리에 접근할 수 없다.

또한 부모 디렉토리를 통과할 수 없으면 하위 디렉토리 권한이 열려 있어도 접근할 수 없다. 예를 들어 `upload_files`가 `agent-common` 그룹에 열려 있더라도, 상위 경로인 `$AGENT_HOME`을 통과할 실행 권한이 없으면 `agent-test`가 `upload_files`까지 도달하지 못할 수 있다.

#### 다음 확인

권한 확인은 현재 작업 계정이 아니라 `sudo` 또는 실제 접근 대상 계정 기준으로 수행한다.

```bash
sudo ls -ld /home
sudo ls -ld /home/agent-admin
sudo ls -ld /home/agent-admin/agent-app
sudo ls -ld /home/agent-admin/agent-app/bin
sudo ls -ld /home/agent-admin/agent-app/upload_files
sudo ls -ld /home/agent-admin/agent-app/api_keys
sudo ls -ld /var/log/agent-app

sudo getfacl /home/agent-admin
sudo getfacl /home/agent-admin/agent-app
sudo getfacl /home/agent-admin/agent-app/upload_files
sudo getfacl /home/agent-admin/agent-app/api_keys
sudo getfacl /var/log/agent-app
```

필요하면 `$AGENT_HOME`에는 `agent-common`의 통과 권한만 ACL로 부여하고, 실제 읽기/쓰기 권한은 `upload_files`에만 부여한다.

### 7.2 제공 앱의 키 경로 검증 기준 차이

#### 증상

과제 설명 기준으로 `AGENT_KEY_PATH`를 키 파일 경로로 설정했을 때 앱의 환경 변수 검증이 실패했다.

```bash
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
```

```text
[2/5] Verifying Environment Variables     [FAIL]
   >>> Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys
```

`AGENT_KEY_PATH`를 디렉토리로 수정한 뒤에는 파일명 검증에서 실패했다.

```text
[3/5] Checking Required Files             [FAIL]
   >>> Missing File: secret.key
   >>>    (Expected location: /home/agent-admin/agent-app/api_keys/secret.key)
```

#### 원인

과제 설명에는 `AGENT_KEY_PATH` 예시가 `$AGENT_HOME/api_keys/t_secret.key`로 되어 있었지만, 제공 앱은 `AGENT_KEY_PATH`를 키 파일이 아니라 키 디렉토리 경로로 검증했다.

또한 실제 앱은 `t_secret.key`가 아니라 `secret.key` 파일명을 기대했다.

#### 해결

실행 대상인 제공 앱의 검증 기준에 맞춰 환경 변수와 키 파일을 수정했다.

```bash
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
```

```bash
echo 'agent_api_key_test' | sudo tee /home/agent-admin/agent-app/api_keys/secret.key > /dev/null
sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/secret.key
sudo chmod 640 /home/agent-admin/agent-app/api_keys/secret.key
```

수정 후 환경 변수 검증과 파일 검증이 모두 `[OK]`로 통과했다.

### 7.3 sshd_config 변경 후에도 22번 포트로 리슨됨

#### 증상

`/etc/ssh/sshd_config.d/agent-hardening.conf`에 `Port 20022`를 설정했지만, 실제 리슨 포트는 계속 `22`로 확인되었다.

```text
tcp   LISTEN 0      4096                0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=3845,fd=3),("systemd",pid=1,fd=115))
tcp   LISTEN 0      4096                   [::]:22            [::]:*    users:(("sshd",pid=3845,fd=4),("systemd",pid=1,fd=116))
```

#### 원인

Ubuntu 24.04 환경에서 SSH가 `ssh.socket` 기반 socket activation으로 동작하고 있었다. 이 경우 `sshd_config`의 `Port` 설정만으로는 systemd socket이 열고 있는 `ListenStream=22`를 변경할 수 없다.

확인 결과 `ssh.socket`은 활성화되어 있었고, 기본 설정에서 `22` 포트를 리슨하고 있었다.

```bash
systemctl is-active ssh.socket
systemctl is-enabled ssh.socket
systemctl cat ssh.socket
```

```text
active
enabled
ListenStream=0.0.0.0:22
ListenStream=[::]:22
```

#### 해결

`ssh.socket` override 설정을 추가해 기존 `ListenStream`을 비우고 `20022`로 재정의했다.

```bash
sudo mkdir -p /etc/systemd/system/ssh.socket.d

sudo tee /etc/systemd/system/ssh.socket.d/listen.conf > /dev/null <<'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:20022
ListenStream=[::]:20022
EOF

sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
```

최종적으로 `ss` 결과에서 `20022` 리슨 상태를 확인했다.
