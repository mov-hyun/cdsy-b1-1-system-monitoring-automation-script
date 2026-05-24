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

### 레포지토리 구조

```text
.
├── README.md
└── bin/
    └── monitor.sh
```

레포지토리의 `bin/monitor.sh`는 실습 서버에서 `$AGENT_HOME/bin/monitor.sh`로 배치해 사용하는 파일입니다.

### 체크리스트

<details>
<summary>요구사항 체크리스트</summary>

- [ ] SSH 포트를 `20022`로 변경했다.
- [ ] root 원격 접속을 차단했다.
- [ ] 방화벽을 활성화하고 인바운드 허용 포트를 `20022/tcp`, `15034/tcp`로 제한했다.
- [ ] `agent-admin`, `agent-dev`, `agent-test` 계정과 `agent-common`, `agent-core` 그룹을 생성했다.
- [ ] `agent-common`에는 admin/dev/test를, `agent-core`에는 admin/dev를 포함했다.
- [ ] `$AGENT_HOME/upload_files`는 `agent-common`, `$AGENT_HOME/api_keys`와 `/var/log/agent-app`은 `agent-core` 권한으로 구성했다.
- [ ] `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 환경 변수를 구성했다.
- [ ] `$AGENT_HOME/api_keys/t_secret.key` 파일을 생성했다.
- [ ] 앱을 일반 계정으로 실행하고 Boot Sequence 5단계 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN 상태를 확인했다.
- [ ] `bin/monitor.sh`를 Bash로 구현하고 실습 서버의 `$AGENT_HOME/bin/monitor.sh`에 배치했다.
- [ ] `monitor.sh` 소유자/그룹/권한을 `agent-dev:agent-core`, `750`으로 설정했다.
- [ ] `monitor.sh`가 앱 프로세스와 `15034/tcp` 포트 비정상 상태에서 `exit 1`로 종료한다.
- [ ] `monitor.sh`가 방화벽 비활성, CPU/MEM/DISK 임계값 초과를 `[WARNING]`으로 출력한다.
- [ ] `monitor.sh`가 CPU/MEM/DISK 사용률을 수집한다.
- [ ] `/var/log/agent-app/monitor.log`에 지정 포맷으로 로그를 누적 기록한다.
- [ ] `monitor.log` 10MB/10개 용량 관리 정책을 구현했다.
- [ ] `agent-admin` crontab에 `monitor.sh` 매분 실행을 등록하고 1분 후 로그 자동 증가를 확인했다.
- [ ] 설정 파일, `ss -tulnp`, `monitor.log` 최근 라인으로 주요 결과를 확인했다.

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
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF

# 앱이 검증할 API 키 파일 생성
echo 'agent_api_key_test' | sudo tee /home/agent-admin/agent-app/api_keys/t_secret.key > /dev/null

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/.env             # 환경 변수 파일 소유자/그룹 설정
sudo chmod 640 /home/agent-admin/agent-app/.env                                # 소유자는 읽기/쓰기, agent-core는 읽기만 허용

sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/t_secret.key # 키 파일 소유자/그룹 설정
sudo chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key                    # 소유자는 읽기/쓰기, agent-core는 읽기만 허용

# 환경 변수와 키 파일 권한 확인
sudo ls -l /home/agent-admin/agent-app/.env
sudo ls -l /home/agent-admin/agent-app/api_keys/t_secret.key

# agent-admin 기준 환경 변수 로드 확인
sudo -u agent-admin bash -lc 'source /home/agent-admin/agent-app/.env && env | grep "^AGENT_" | sort'

# agent-admin은 키 파일을 읽을 수 있어야 함
sudo -u agent-admin cat /home/agent-admin/agent-app/api_keys/t_secret.key

# agent-test는 키 파일을 읽을 수 없어야 함
sudo -u agent-test cat /home/agent-admin/agent-app/api_keys/t_secret.key
```

#### 확인 결과

```text
-rw-r----- 1 agent-admin agent-core 247 May 24 18:18 /home/agent-admin/agent-app/.env
-rw-r----- 1 agent-admin agent-core 19 May 24 18:18 /home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_HOME=/home/agent-admin/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
agent_api_key_test
cat: /home/agent-admin/agent-app/api_keys/t_secret.key: Permission denied
```

#### 정리

- 실행 계정: `agent-admin`
- 환경 변수 파일: `/home/agent-admin/agent-app/.env`
- 키 파일: `/home/agent-admin/agent-app/api_keys/t_secret.key`
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
TODO
```

#### 확인 결과

```text
TODO
```

#### 정리

- SSH 포트: TODO
- root 원격 접속 차단: TODO
- `sshd` 리슨 상태: TODO

### 4.6 방화벽 설정

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 정리

- 선택 도구: TODO
- 허용 포트: TODO
- 활성화 상태: TODO

### 4.7 monitor.sh

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 정리

- 경로: TODO
- 소유자/그룹/권한: TODO
- 프로세스 점검: TODO
- 포트 점검: TODO
- 자원 수집: TODO
- 경고 조건: TODO
- 로그 기록: TODO
- 로그 용량 관리: TODO

### 4.8 cron 자동 실행

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 정리

- 실행 계정: TODO
- 등록 주기: TODO
- 로그 증가 확인: TODO

---

## 5. 장애 상황 대응

- 모니터링 대상이 Nginx 등 웹 서버로 바뀌면 수정할 핵심 포인트: TODO
- 프로세스는 살아있지만 포트가 열리지 않은 상황의 원인 후보와 확인 순서: TODO
- 로그 급증으로 디스크가 가득 찰 위험이 있을 때 단기/중기 대응: TODO

---

## 6. 보너스 과제

- `report.sh` 요약 리포트: TODO
- 시간 기반 로그 보존 정책: TODO

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
