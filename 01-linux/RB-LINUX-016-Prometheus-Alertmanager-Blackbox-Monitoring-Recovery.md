# RB-LINUX-016 — Prometheus, Alertmanager, and Blackbox Monitoring Recovery

## Purpose

Document the diagnosis and recovery of a monitoring-stack outage on `ubuntu-devops01` in which Prometheus, Alertmanager, and Blackbox Exporter stopped reporting to Glance.

The incident ultimately exposed Docker Compose configuration drift between two monitoring directories and an invalid Compose configuration.

---

## Environment

**Host:** `ubuntu-devops01`

**Canonical monitoring project:**

```text
/home/brettcoder/monitoring-lab
```

**Monitoring components:**

| Service | Port | Purpose |
|---|---:|---|
| Prometheus | 9090 | Metrics collection and monitoring |
| Alertmanager | 9093 | Alert routing and notification |
| Blackbox Exporter | 9115 | Network/service probing |
| Node Exporter | 9100 | Linux host metrics |
| Grafana | 3000 | Metrics visualization |
| Glance | 8081 | Dashboard/service status display |

---

# Incident Summary

Glance reported that Prometheus, Alertmanager, and Blackbox Exporter were unavailable.

Initial investigation confirmed that the issue was not limited to Glance. None of the three applications were listening on their expected ports, and localhost HTTP requests failed.

```text
Prometheus:   000
Alertmanager: 000
Blackbox:     000
```

Systemd did not report any failed services because the monitoring applications were running as Docker containers rather than native systemd services.

---

# Initial Investigation

## Check Failed systemd Services

```bash
systemctl --type=service --state=failed
```

Result:

```text
0 loaded units listed.
```

This demonstrated that a clean systemd failure report does not prove all applications on the server are healthy.

---

## Check Monitoring Ports

```bash
ss -lntp | grep -E ':(9090|9093|9115)\b'
```

No listeners were returned.

Expected ports:

```text
9090  Prometheus
9093  Alertmanager
9115  Blackbox Exporter
```

---

## Test Applications Locally

```bash
curl -sS -o /dev/null -w 'Prometheus: %{http_code}\n' http://localhost:9090/-/healthy

curl -sS -o /dev/null -w 'Alertmanager: %{http_code}\n' http://localhost:9093/-/healthy

curl -sS -o /dev/null -w 'Blackbox: %{http_code}\n' http://localhost:9115/
```

Initial results:

```text
Prometheus: 000
Alertmanager: 000
Blackbox: 000
```

All connections were refused.

---

# Docker Investigation

## Check All Containers

```bash
docker ps -a
```

Relevant results:

```text
prometheus     Exited (0)   5 days ago
alertmanager   Exited (127) 5 days ago
blackbox       Exited (127) 5 days ago
node-exporter  Up
grafana        Up
```

This isolated the problem to the monitoring containers.

---

## Examine Container Logs

### Prometheus

```bash
docker logs --tail 30 prometheus
```

Important event:

```text
Received an OS signal, exiting gracefully... signal=terminated
```

### Alertmanager

```bash
docker logs --tail 30 alertmanager
```

Important event:

```text
Received SIGTERM, exiting gracefully...
```

### Blackbox

```bash
docker logs --tail 30 blackbox
```

Important event:

```text
Received SIGTERM, exiting gracefully...
```

All three containers were terminated at approximately the same time:

```text
2026-08-17 02:12
```

This indicated a container lifecycle/configuration event rather than three unrelated application crashes.

---

# Restart Policy Verification

```bash
docker inspect prometheus alertmanager blackbox \
  --format '{{.Name}} | Exit={{.State.ExitCode}} | Finished={{.State.FinishedAt}} | Restart={{.HostConfig.RestartPolicy.Name}}'
```

Results:

```text
/prometheus   | Exit=0   | Restart=unless-stopped
/alertmanager | Exit=127 | Restart=unless-stopped
/blackbox     | Exit=127 | Restart=unless-stopped
```

All containers were configured with:

```text
restart: unless-stopped
```

---

# Compose Project Investigation

## Identify Compose Metadata

```bash
docker inspect prometheus alertmanager blackbox \
  --format '{{.Name}} | Project={{index .Config.Labels "com.docker.compose.project"}} | WorkingDir={{index .Config.Labels "com.docker.compose.project.working_dir"}} | Config={{index .Config.Labels "com.docker.compose.project.config_files"}}'
```

Results:

```text
/prometheus
Project=monitoring
WorkingDir=/home/brettcoder/monitoring-lab

/alertmanager
Project=monitoring
WorkingDir=/home/brettcoder/monitoring

/blackbox
Project=monitoring
WorkingDir=/home/brettcoder/monitoring
```

This exposed configuration drift between:

```text
/home/brettcoder/monitoring-lab
```

and:

```text
/home/brettcoder/monitoring
```

---

# Filesystem Investigation

The canonical project contained valid configuration files:

```text
~/monitoring-lab/
├── prometheus/prometheus.yml
├── alertmanager/alertmanager.yml
├── blackbox/blackbox.yml
└── docker-compose.yml
```

The duplicate monitoring directory contained directories where YAML configuration files should have existed:

```text
~/monitoring/
├── prometheus/
│   └── prometheus.yml/
├── alertmanager/
│   └── alertmanager.yml/
└── blackbox/
    └── blackbox.yml/
```

Verification:

```bash
sudo find ~/monitoring -maxdepth 3 -printf '%y %p\n'
```

Result:

```text
d /home/brettcoder/monitoring
d /home/brettcoder/monitoring/prometheus
d /home/brettcoder/monitoring/prometheus/prometheus.yml
d /home/brettcoder/monitoring/blackbox
d /home/brettcoder/monitoring/blackbox/blackbox.yml
d /home/brettcoder/monitoring/alertmanager
d /home/brettcoder/monitoring/alertmanager/alertmanager.yml
```

`d` confirmed these were directories rather than regular files.

---

# Bind-Mount Investigation

```bash
docker inspect prometheus alertmanager blackbox \
  --format '{{.Name}} | {{range .Mounts}}{{.Source}} -> {{.Destination}}; {{end}}'
```

Prometheus was correctly mounted from:

```text
/home/brettcoder/monitoring-lab/prometheus/prometheus.yml
```

Alertmanager incorrectly referenced:

```text
/home/brettcoder/monitoring/alertmanager/alertmanager.yml
```

Blackbox incorrectly referenced:

```text
/home/brettcoder/monitoring/blackbox/blackbox.yml
```

The latter two paths were directories rather than valid configuration files.

---

# Docker Compose Configuration Error

The canonical Compose definition was validated with:

```bash
cd ~/monitoring-lab
docker compose config
```

Initial result:

```text
failed to parse docker-compose.yml:
mapping key "node-exporter" already defined
```

The Compose file contained two separate `node-exporter:` definitions.

A backup was created before correction:

```bash
cp docker-compose.yml docker-compose.yml.pre-rb016
```

The duplicate `node-exporter` service definition was removed.

The retained definition included:

```yaml
node-exporter:
  image: prom/node-exporter:latest
  container_name: node-exporter
  restart: unless-stopped
  pid: host
  network_mode: host
  command:
    - '--path.rootfs=/host'
  volumes:
    - '/:/host:ro,rslave'
```

Validation after repair:

```bash
docker compose config >/dev/null && echo "Compose: VALID"
```

Result:

```text
Compose: VALID
```

---

# Recovery

## Remove Stale Alertmanager and Blackbox Containers

The stale containers still owned their fixed container names, preventing Compose from recreating them.

```bash
docker rm alertmanager blackbox
```

They were then recreated from the canonical monitoring directory:

```bash
cd ~/monitoring-lab
docker compose up -d alertmanager blackbox
```

Verification:

```bash
docker ps --filter name=alertmanager --filter name=blackbox
```

Both containers returned to the `Up` state.

---

## Verify Correct Bind Mounts

```bash
docker inspect alertmanager blackbox \
  --format '{{.Name}} | {{range .Mounts}}{{.Source}} -> {{.Destination}}; {{end}}'
```

Corrected paths:

```text
/home/brettcoder/monitoring-lab/alertmanager/alertmanager.yml
/home/brettcoder/monitoring-lab/blackbox/blackbox.yml
```

---

## Restore Prometheus

The stale Prometheus container also still owned the fixed container name.

Remove it:

```bash
docker rm prometheus
```

Recreate it from the canonical Compose project:

```bash
cd ~/monitoring-lab
docker compose up -d prometheus
```

---

# Final Verification

## Validate Compose Configuration

```bash
docker compose config >/dev/null && echo "Compose: VALID"
```

Result:

```text
Compose: VALID
```

---

## Verify Container State

```bash
docker compose ps
```

Final result:

```text
NAME           STATUS
alertmanager   Up
blackbox       Up
prometheus     Up
```

---

## Verify Bind Mounts

```bash
docker inspect prometheus alertmanager blackbox \
  --format '{{.Name}} | {{range .Mounts}}{{.Source}} -> {{.Destination}}; {{end}}'
```

Final configuration paths:

```text
Prometheus:
~/monitoring-lab/prometheus/prometheus.yml

Alertmanager:
~/monitoring-lab/alertmanager/alertmanager.yml

Blackbox:
~/monitoring-lab/blackbox/blackbox.yml
```

All application configuration is now sourced from the canonical monitoring repository.

---

## HTTP Health Checks

```bash
curl -sS -o /dev/null -w 'Prometheus: %{http_code}\n' \
  http://localhost:9090/-/healthy

curl -sS -o /dev/null -w 'Alertmanager: %{http_code}\n' \
  http://localhost:9093/-/healthy

curl -sS -o /dev/null -w 'Blackbox: %{http_code}\n' \
  http://localhost:9115/
```

Final results:

```text
Prometheus: 200
Alertmanager: 200
Blackbox: 200
```

All three services were also confirmed accessible through a web browser and restored in Glance.

---

# Filesystem Cleanup

The following directory was established as the authoritative monitoring project:

```text
/home/brettcoder/monitoring-lab
```

The obsolete duplicate directory:

```text
/home/brettcoder/monitoring
```

was removed after validating that no running container depended on it.

Old Compose backup files were also reduced.

Removed:

```text
docker-compose.yml.bak
docker-compose.yml.save
docker-compose.yml.save.1
docker-compose.yml.save.2
```

Temporarily retained:

```text
docker-compose.yml
docker-compose.yml.pre-rb016
```

Git should be used for long-term configuration history rather than accumulating manual `.save` files.

---

# Final Project Structure

```text
~/monitoring-lab/
├── .git/
├── .gitignore
├── alertmanager/
│   └── alertmanager.yml
├── assets/
│   ├── diagrams/
│   └── screenshots/
├── blackbox/
│   └── blackbox.yml
├── docker-compose.yml
├── docker-compose.yml.pre-rb016
├── docs/
├── grafana/
│   ├── dashboards/
│   └── provisioning/
├── journal/
├── LAB_STATUS.md
├── prometheus/
│   ├── prometheus.yml
│   └── prometheus.yml.backup-20260814-1050
└── README.md
```

---

# Root Cause

The outage was caused by **Docker Compose configuration drift**.

The monitoring environment had been operated from two separate working directories:

```text
~/monitoring-lab
~/monitoring
```

Prometheus remained associated with the intended `monitoring-lab` directory, while Alertmanager and Blackbox were associated with the unintended `monitoring` directory.

Relative bind-mount paths under the incorrect directory resulted in paths intended to contain YAML configuration files becoming directories instead.

The canonical `docker-compose.yml` also contained a duplicate `node-exporter` service definition, preventing Compose from successfully parsing the project until the configuration was repaired.

The affected containers were subsequently removed and recreated from the canonical `~/monitoring-lab` project.

---

# Troubleshooting Decision Path

```text
Glance reports monitoring services unavailable
        |
        v
Check expected ports
9090 / 9093 / 9115 not listening
        |
        v
Test localhost endpoints
Connections refused
        |
        v
Check systemd failures
No failed services
        |
        v
Check Docker
Prometheus / Alertmanager / Blackbox stopped
        |
        v
Inspect logs
All received SIGTERM at approximately same time
        |
        v
Inspect Compose metadata
Different working directories discovered
        |
        v
Inspect bind mounts
Alertmanager / Blackbox pointed to ~/monitoring
        |
        v
Inspect filesystem
Expected YAML files were directories
        |
        v
Validate Compose
Duplicate node-exporter key discovered
        |
        v
Repair canonical docker-compose.yml
        |
        v
Remove stale containers
        |
        v
Recreate from ~/monitoring-lab
        |
        v
Verify mounts + HTTP health
        |
        v
Monitoring restored
```

---

# Lessons Learned

## 1. `systemctl` Does Not Represent Every Application

A server can show:

```text
0 failed units
```

while important workloads are unavailable if those workloads are managed by Docker, Kubernetes, another process supervisor, or an application-specific runtime.

Always determine how the workload is actually managed.

---

## 2. An Inactive Container Is Different From a Failed systemd Service

Docker container state must be checked independently:

```bash
docker ps -a
```

---

## 3. Docker Compose Working Directory Matters

Relative paths such as:

```yaml
./alertmanager/alertmanager.yml
```

are resolved relative to the Compose project directory.

Running Compose from the wrong project location can therefore change which host files are mounted into containers.

---

## 4. Verify Bind Mounts From the Running Container

Do not assume the Compose file represents the configuration actually in use.

Check:

```bash
docker inspect <container>
```

The running container's mount metadata provides direct evidence of which host configuration is being consumed.

---

## 5. Validate Compose Before Deployment

Use:

```bash
docker compose config
```

before:

```bash
docker compose up -d
```

This catches malformed YAML, duplicate service definitions, and path-resolution problems before deployment.

---

## 6. Fixed Container Names Can Block Recreation

An exited container still owns its container name.

For example:

```text
Conflict. The container name "/blackbox" is already in use
```

The old container may need to be removed before Compose can recreate it:

```bash
docker rm blackbox
```

---

## 7. Use Git Instead of Accumulating Manual Configuration Backups

Files such as:

```text
docker-compose.yml.save
docker-compose.yml.save.1
docker-compose.yml.save.2
```

create clutter and make determining the authoritative configuration more difficult.

Once configuration is properly committed, Git provides better version history and rollback capability.

---

# Command Reference

| Command | Purpose |
|---|---|
| `systemctl --type=service --state=failed` | Display systemd services currently in a failed state |
| `ss -lntp` | Display listening TCP sockets and associated processes |
| `grep -E` | Filter text using extended regular expressions |
| `curl` | Test HTTP endpoints and application health |
| `docker ps` | Display running Docker containers |
| `docker ps -a` | Display running and stopped containers |
| `docker logs` | Display container application logs |
| `docker inspect` | Display detailed Docker container metadata |
| `docker compose ls -a` | List Compose projects including stopped projects |
| `docker compose config` | Parse, normalize, and validate a Compose configuration |
| `docker compose ps` | Display containers associated with the current Compose project |
| `docker compose up -d` | Create/start Compose services in detached mode |
| `docker compose up -d --force-recreate` | Recreate containers even when configuration appears unchanged |
| `docker rm <container>` | Remove a stopped Docker container |
| `find` | Search filesystem paths and inspect file types |
| `diff -qr` | Recursively compare directory structures and report differences |
| `diff -u` | Compare files using unified diff format |
| `cp` | Copy files, including temporary configuration backups |
| `rm` | Remove files |
| `rm -rf` | Recursively remove a directory tree; use cautiously |
| `tree` | Display a hierarchical directory structure |
| `ls -la` | Display files including hidden files with detailed metadata |
| `history` | Display shell command history |
| `last -x` | Display login, reboot, shutdown, and runlevel history |
| `journalctl -u docker` | Query systemd journal entries for the Docker daemon |

---

# Useful Operational Checks

## Monitoring Container Status

```bash
cd ~/monitoring-lab
docker compose ps
```

## Validate Compose

```bash
docker compose config >/dev/null && echo "Compose: VALID"
```

## Verify Monitoring Ports

```bash
ss -lntp | grep -E ':(9090|9093|9115)\b'
```

## Verify Health Endpoints

```bash
curl -sS -o /dev/null -w 'Prometheus: %{http_code}\n' \
  http://localhost:9090/-/healthy

curl -sS -o /dev/null -w 'Alertmanager: %{http_code}\n' \
  http://localhost:9093/-/healthy

curl -sS -o /dev/null -w 'Blackbox: %{http_code}\n' \
  http://localhost:9115/
```

Expected:

```text
Prometheus: 200
Alertmanager: 200
Blackbox: 200
```

## Verify Configuration Sources

```bash
docker inspect prometheus alertmanager blackbox \
  --format '{{.Name}} | {{range .Mounts}}{{.Source}} -> {{.Destination}}; {{end}}'
```

All configuration bind mounts should resolve beneath:

```text
/home/brettcoder/monitoring-lab
```

---

# Resolution

**Status:** Resolved

Prometheus, Alertmanager, and Blackbox Exporter were restored successfully.

The monitoring stack now uses a single authoritative Compose project:

```text
/home/brettcoder/monitoring-lab
```

Compose validation succeeds, all affected containers are running with the correct bind mounts, all three application health checks return HTTP `200`, and monitoring visibility through Glance has been restored.