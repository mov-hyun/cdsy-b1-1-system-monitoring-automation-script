# 시스템 관제 자동화 스크립트 개발

Linux 서버 운영 환경을 구성하고, 제공 Agent 앱의 상태를 Bash 스크립트로 관제하는 과제입니다.

## 목차

1. [과제 개요](#1-과제-개요)
2. [제출 산출물](#2-제출-산출물)
3. [실습 환경 및 필수 도구 확인](#3-실습-환경-및-필수-도구-확인)
4. [레포지토리 구조](#4-레포지토리-구조)
5. [핵심 개념 정리](#5-핵심-개념-정리)
6. [체크리스트](#6-체크리스트)
7. [수행 내역](#7-수행-내역)
8. [구현 방식 설명](#8-구현-방식-설명)
9. [보안 및 운영 개념 설명](#9-보안-및-운영-개념-설명)
10. [장애 상황 대응](#10-장애-상황-대응)
11. [보너스 과제](#11-보너스-과제)

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

## 2. 제출 산출물

1. 요구사항 수행 내역서: 이 `README.md`
2. 자동화 스크립트: `bin/monitor.sh`

## 3. 실습 환경 및 필수 도구 확인

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

## 4. 레포지토리 구조

```text
.
├── README.md
└── bin/
    └── monitor.sh
```

레포지토리의 `bin/monitor.sh`는 실습 서버에서 `$AGENT_HOME/bin/monitor.sh`로 배치해 사용하는 파일입니다.

## 5. 핵심 개념 정리

### 5.1 SSH 포트 변경과 root 접속 차단

SSH는 원격 서버에 터미널로 접속하기 위한 프로토콜입니다. 기본 포트는 `22/tcp`이지만, 이 과제에서는 `20022/tcp`로 변경합니다.

root 원격 접속을 차단하는 이유는 관리자 권한 계정이 직접 외부 로그인 대상이 되는 위험을 줄이기 위해서입니다. 운영 환경에서는 일반 계정으로 접속한 뒤 필요한 경우에만 `sudo`를 사용하는 방식이 더 안전합니다.

### 5.2 방화벽과 최소 포트 허용

방화벽은 서버로 들어오는 네트워크 접근을 제어합니다. 이 과제에서는 SSH용 `20022/tcp`와 앱용 `15034/tcp`만 허용합니다.

필요한 포트만 열어 두면 사용하지 않는 서비스가 외부 공격면이 되는 위험을 줄일 수 있습니다.

### 5.3 계정, 그룹, 최소 권한

여러 사용자가 같은 서버를 사용할 때는 역할에 따라 계정과 그룹을 분리해야 합니다.

- `agent-admin`: 운영 및 cron 실행 계정
- `agent-dev`: 스크립트 작성 및 관리 계정
- `agent-test`: 테스트 계정
- `agent-common`: 공용 업로드 디렉토리 접근 그룹
- `agent-core`: 민감 디렉토리 접근 그룹

최소 권한 원칙은 각 사용자와 프로세스가 필요한 권한만 갖도록 제한하는 운영 원칙입니다.

### 5.4 디렉토리 권한과 ACL

`upload_files`는 공용 작업 공간이므로 `agent-common` 그룹에 읽기/쓰기 권한을 부여합니다.

`api_keys`와 `/var/log/agent-app`은 민감 정보와 운영 로그를 포함하므로 `agent-core` 그룹으로 접근을 제한합니다.

필요하면 ACL을 사용해 기본 Unix 권한보다 더 세밀한 접근 제어를 적용할 수 있습니다. 예를 들어 디렉토리의 소유자/그룹 권한만으로 표현하기 어려운 접근 정책은 `setfacl`로 부여하고, `getfacl`로 실제 적용 상태를 확인할 수 있습니다.

### 5.5 환경 변수로 실행 환경 고정

환경 변수는 앱이 실행될 때 참조할 경로와 포트 값을 외부에서 주입하는 방식입니다.

이 과제에서는 `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR`을 사용해 앱 실행 환경을 명확히 고정합니다.

### 5.6 Health Check와 Warning 분리

프로세스 미실행이나 포트 미개방은 앱이 정상 서비스 상태가 아니므로 `monitor.sh`가 `exit 1`로 종료해야 합니다.

반면 방화벽 비활성, CPU/MEM/DISK 임계치 초과는 운영자가 확인해야 할 경고 상황이므로 `[WARNING]`을 출력하되 스크립트는 계속 진행합니다.

이렇게 분리하면 서비스 가용성에 직접 영향을 주는 장애와, 운영자가 추적해야 하는 위험 신호를 구분할 수 있습니다.

### 5.7 로그 누적과 리다이렉션

`>`는 파일을 새로 덮어쓰고, `>>`는 기존 파일 뒤에 내용을 추가합니다.

모니터링 로그는 시간 순서대로 누적되어야 하므로 `monitor.log` 기록에는 `>>`를 사용해야 합니다.

### 5.8 cron 자동 실행

cron은 정해진 시간 주기에 명령을 자동 실행하는 Linux 스케줄러입니다.

이 과제에서는 `agent-admin` 계정의 crontab에 `monitor.sh`를 매분 실행하도록 등록합니다.

cron은 비대화형 환경에서 실행되므로 스크립트 안에서는 필요한 경로를 명확히 지정해야 합니다. 상대 경로나 현재 쉘에만 설정된 환경 변수에 의존하면 수동 실행은 성공하지만 cron 실행은 실패할 수 있습니다.

### 5.9 로그 용량 관리

모니터링 로그는 계속 누적되므로 용량 관리가 필요합니다. 이 과제에서는 `monitor.log`가 커질 때 10MB/10개 기준으로 관리합니다.

구현 방식은 logrotate를 사용하거나, `monitor.sh` 내부에서 직접 회전 로직을 작성할 수 있습니다.

logrotate는 운영체제의 표준 로그 관리 방식이고, 스크립트 내부 회전 로직은 제출 파일만으로 동작을 설명하기 쉽다는 장점이 있습니다. 최종 구현에서는 선택한 방식과 이유를 기록합니다.

### 5.10 상태 확인 명령

프로세스 확인에는 `pgrep` 또는 `ps`를 사용할 수 있습니다. `pgrep`은 프로세스 이름이나 실행 인자를 기준으로 PID를 찾기 쉽고, `ps`는 더 자세한 프로세스 정보를 확인할 수 있습니다.

포트 확인에는 `ss` 또는 `netstat`를 사용할 수 있습니다. 최신 Linux 환경에서는 `ss`가 기본 도구로 더 적합하며, LISTEN 상태의 TCP 포트를 확인하는 데 사용합니다.

## 6. 체크리스트

- [ ] SSH 포트를 `20022`로 변경했다.
- [ ] root 원격 접속을 차단했다.
- [ ] 방화벽을 활성화했다.
- [ ] 인바운드 허용 포트를 `20022/tcp`, `15034/tcp`로 제한했다.
- [ ] `agent-admin`, `agent-dev`, `agent-test` 계정을 생성했다.
- [ ] `agent-common`, `agent-core` 그룹을 생성했다.
- [ ] `agent-common`에 `agent-admin`, `agent-dev`, `agent-test`를 포함했다.
- [ ] `agent-core`에 `agent-admin`, `agent-dev`를 포함했다.
- [ ] `$AGENT_HOME/upload_files`를 `agent-common` 그룹이 읽고 쓸 수 있게 구성했다.
- [ ] `$AGENT_HOME/api_keys`를 `agent-core` 그룹만 읽고 쓸 수 있게 구성했다.
- [ ] `/var/log/agent-app`을 `agent-core` 그룹만 읽고 쓸 수 있게 구성했다.
- [ ] `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 환경 변수를 구성했다.
- [ ] `$AGENT_HOME/api_keys/t_secret.key` 파일을 생성했다.
- [ ] 앱 Boot Sequence 5단계가 모두 `[OK]`로 통과했다.
- [ ] 앱에서 `Agent READY`가 출력되었다.
- [ ] 앱이 `0.0.0.0:15034`에서 LISTEN 상태임을 확인했다.
- [ ] 앱을 root가 아닌 일반 계정으로 실행했다.
- [ ] `bin/monitor.sh`를 Bash로 구현했다.
- [ ] 실습 서버에서 `monitor.sh`를 `$AGENT_HOME/bin/monitor.sh`에 배치했다.
- [ ] `monitor.sh` 소유자를 `agent-dev`로 설정했다.
- [ ] `monitor.sh` 그룹을 `agent-core`로 설정했다.
- [ ] `monitor.sh` 권한을 `750`으로 설정했다.
- [ ] `monitor.sh`가 앱 프로세스 미실행 시 `exit 1`로 종료한다.
- [ ] `monitor.sh`가 `15034/tcp` 포트 미개방 시 `exit 1`로 종료한다.
- [ ] `monitor.sh`가 방화벽 비활성 상태를 `[WARNING]`으로 출력한다.
- [ ] `monitor.sh`가 CPU/MEM/DISK 사용률을 수집한다.
- [ ] `monitor.sh`가 임계값 초과를 `[WARNING]`으로 출력한다.
- [ ] `/var/log/agent-app/monitor.log`에 지정 포맷으로 로그를 누적 기록한다.
- [ ] `monitor.log` 10MB/10개 용량 관리 정책을 구현했다.
- [ ] cron 실행 계정이 `agent-admin`임을 확인했다.
- [ ] `agent-admin` crontab에 `monitor.sh` 매분 실행을 등록했다.
- [ ] 1분 후 `monitor.log`가 자동 증가하는 것을 확인했다.
- [ ] SSH 설정 파일에서 `Port 20022`와 `PermitRootLogin no`를 확인했다.
- [ ] `ss -tulnp`로 `sshd`의 `20022` LISTEN 상태를 확인했다.
- [ ] `ss -tulnp`로 Agent 앱의 `15034` LISTEN 상태를 확인했다.
- [ ] `/var/log/agent-app/monitor.log`의 최근 라인을 확인했다.

## 7. 수행 내역

### 7.1 SSH 설정

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- SSH 포트: TODO
- root 원격 접속 차단: TODO
- `sshd` 리슨 상태: TODO

### 7.2 방화벽 설정

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- 선택 도구: TODO
- 허용 포트: TODO
- 활성화 상태: TODO

### 7.3 계정과 그룹

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- 생성 계정: TODO
- 생성 그룹: TODO
- 그룹 포함 관계: TODO

### 7.4 디렉토리와 권한

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- `AGENT_HOME`: TODO
- `upload_files` 권한: TODO
- `api_keys` 권한: TODO
- `/var/log/agent-app` 권한: TODO
- ACL 사용 여부: TODO

### 7.5 앱 실행

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- 실행 계정: TODO
- 환경 변수: TODO
- 키 파일: TODO
- Boot Sequence 결과: TODO
- 포트 LISTEN 확인: TODO

### 7.6 monitor.sh

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- 경로: TODO
- 소유자/그룹/권한: TODO
- 프로세스 점검: TODO
- 포트 점검: TODO
- 자원 수집: TODO
- 경고 조건: TODO
- 로그 기록: TODO
- 로그 용량 관리: TODO

### 7.7 cron 자동 실행

#### 실행 명령

```bash
TODO
```

#### 확인 결과

```text
TODO
```

#### 판단

- 실행 계정: TODO
- 등록 주기: TODO
- 로그 증가 확인: TODO

## 8. 구현 방식 설명

- 프로세스 식별에 사용한 명령과 선택 이유: TODO
- 포트 확인에 사용한 명령과 선택 이유: TODO
- CPU/MEM/DISK 값을 추출하고 파싱한 방식: TODO
- 로그 포맷을 고정한 이유: TODO
- `agent-dev` 소유자와 `agent-admin` 실행자 권한 정책 설명: TODO
- 로그 용량 관리를 구현한 방식: TODO

## 9. 보안 및 운영 개념 설명

- SSH 포트 변경과 root 접속 차단이 보안에 효과적인 이유: TODO
- `api_keys`와 로그 디렉토리를 `agent-core`로 제한한 이유: TODO
- 방화벽 비활성/임계치 초과를 종료가 아닌 경고로 처리한 이유: TODO
- 리다이렉션 `>`와 `>>` 차이 및 로그 누적에 `>>`가 필요한 이유: TODO

## 10. 장애 상황 대응

- 모니터링 대상이 Nginx 등 웹 서버로 바뀌면 수정할 핵심 포인트: TODO
- 프로세스는 살아있지만 포트가 열리지 않은 상황의 원인 후보와 확인 순서: TODO
- 로그 급증으로 디스크가 가득 찰 위험이 있을 때 단기/중기 대응: TODO

## 11. 보너스 과제

- `report.sh` 요약 리포트: TODO
- 시간 기반 로그 보존 정책: TODO
