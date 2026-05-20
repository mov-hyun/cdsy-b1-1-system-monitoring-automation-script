# Submission Report

## 1. Environment

- Host:
- Virtualization tool:
- Guest OS:
- Architecture:
- App binary:
- `AGENT_HOME`:

## 2. Security and Network Configuration

### SSH

- SSH port:
- Root remote login:
- Configuration file:
- Verification command:
- Result:

### Firewall

- Firewall tool:
- Allowed inbound ports:
- Verification command:
- Result:

## 3. Users, Groups, and Permissions

### Users

- `agent-admin`:
- `agent-dev`:
- `agent-test`:

### Groups

- `agent-common`:
- `agent-core`:

### Directories

- `$AGENT_HOME`:
- `$AGENT_HOME/upload_files`:
- `$AGENT_HOME/api_keys`:
- `/var/log/agent-app`:

### Permission Evidence

- `id` output:
- `ls -l` output:
- `getfacl` output:

## 4. Agent App Execution

### Environment Variables

- `AGENT_HOME`:
- `AGENT_PORT`:
- `AGENT_UPLOAD_DIR`:
- `AGENT_KEY_PATH`:
- `AGENT_LOG_DIR`:

### Boot Sequence Evidence

```text
Paste boot sequence output here.
```

### Port Listening Evidence

```text
Paste ss output here.
```

## 5. monitor.sh

- Path:
- Owner:
- Group:
- Permission:
- Cron user:

### Manual Execution Evidence

```text
Paste monitor.sh output here.
```

### Log Evidence

```text
Paste recent /var/log/agent-app/monitor.log lines here.
```

## 6. Cron Verification

- Crontab command:
- Registered entry:
- Verification method:
- Result:

```text
Paste before/after log line counts or recent log lines here.
```

## 7. Log Retention Policy

- Method:
- Max size:
- Max file count:
- Verification:

## 8. Notes

- Assumptions:
- Deviations from Ubuntu 22.04, if any:
