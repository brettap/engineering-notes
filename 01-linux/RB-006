[200~# RB-0006 — systemd Service Administration & Troubleshooting

## Purpose

Practice administering, monitoring, troubleshooting, recovering, and validating a Linux service managed by `systemd`.

This lab simulates an L2 NOC/System Administrator workflow:

* Deploy a long-running application.
* Create and administer a `systemd` service.
* Verify service state versus actual application functionality.
* Configure automatic recovery.
* Configure boot persistence.
* Diagnose a failed service.
* Interpret `203/EXEC`.
* Perform root-cause analysis.
* Restore service.
* Functionally validate recovery.
* Validate a unit before deployment.

---

## Environment

| Component             | Value                                 |
| --------------------- | ------------------------------------- |
| Host                  | `devops02`                            |
| OS                    | Ubuntu Linux                          |
| Application           | NOC Training Application              |
| Application directory | `/opt/noc-lab`                        |
| Application script    | `/opt/noc-lab/noc-app.sh`             |
| systemd unit          | `/etc/systemd/system/noc-app.service` |
| Application log       | `/var/log/noc-app.log`                |
| Service               | `noc-app.service`                     |

---

# 1. Initial System Baseline

Before making changes, establish the current state of the server.

```bash
hostname
uptime
systemctl --failed
```

### Command purposes

**`hostname`**

Identifies the server currently being administered.

**`uptime`**

Displays how long the server has been running and its load averages.

**`systemctl --failed`**

Lists systemd units currently in a failed state.

This provides a baseline before deploying or troubleshooting an application.

---

# 2. Deploy the Training Application

Create the application directory:

```bash
sudo mkdir -p /opt/noc-lab
```

Create the application:

```bash
sudo nano /opt/noc-lab/noc-app.sh
```

Application contents:

```bash
#!/bin/bash

while true
do
    echo "$(date) - NOC application running" >> /var/log/noc-app.log
    sleep 10
done
```

Make the script executable:

```bash
sudo chmod +x /opt/noc-lab/noc-app.sh
```

Verify:

```bash
ls -l /opt/noc-lab/noc-app.sh
```

Expected executable permissions include:

```text
-rwxr-xr-x
```

---

## Understanding the Application

The application uses:

```bash
while true
```

to create an infinite loop.

`true` continually returns a successful exit status, so the loop continues until the process is terminated.

Application workflow:

```text
START
  │
  ▼
while true
  │
  ▼
Write timestamp to
/var/log/noc-app.log
  │
  ▼
Sleep 10 seconds
  │
  └───────────────┐
                  │
                  ▼
              Repeat
```

Because this process is designed to run continuously, it is an appropriate workload for a service manager such as `systemd`.

---

# 3. Create the systemd Unit

Create:

```bash
sudo nano /etc/systemd/system/noc-app.service
```

Configuration:

```ini
[Unit]
Description=NOC Training Application
After=network.target

[Service]
Type=simple
ExecStart=/opt/noc-lab/noc-app.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Reload the systemd manager configuration:

```bash
sudo systemctl daemon-reload
```

Inspect the loaded unit:

```bash
systemctl cat noc-app
```

---

# 4. Important Unit Directives

## ExecStart

```ini
ExecStart=/opt/noc-lab/noc-app.sh
```

Defines the command that systemd executes when starting the service.

---

## Restart

```ini
Restart=on-failure
```

Tells systemd to restart the service when the process terminates in a manner systemd considers a failure.

This provides automatic service recovery.

It does **not** mean every process termination will cause a restart.

---

## WantedBy

```ini
WantedBy=multi-user.target
```

Defines the target with which this service should be associated when enabled.

It does **not** determine who can access the application.

`multi-user.target` represents a normal multi-user operating state and is conceptually similar to traditional runlevel 3.

---

# 5. Start the Service

Start the application:

```bash
sudo systemctl start noc-app
```

Check its state:

```bash
systemctl status noc-app
```

Another method:

```bash
systemctl list-units --type=service | grep 'noc-app'
```

---

# 6. Process-Level Investigation

## Find the process

```bash
pgrep -a noc-app
```

`pgrep` searches the process table for matching processes.

`-a` displays the PID and full command line.

Example:

```text
4132 /bin/bash /opt/noc-lab/noc-app.sh
```

---

## View process hierarchy/details

```bash
ps -ef | grep '[n]oc-app'
```

`ps -ef` displays running processes in full-format output.

Using:

```text
[n]oc-app
```

prevents the `grep` process itself from matching the search.

---

## Obtain the systemd Main PID

```bash
systemctl show noc-app -p MainPID
```

Example:

```text
MainPID=4933
```

This identifies the primary process systemd is supervising.

---

## Examine files opened by a process

```bash
sudo lsof -p <PID>
```

`lsof` shows files, devices, pipes, sockets, and other file descriptors opened by the process.

Useful when determining what resources an application is actively using.

---

## Inspect network listeners

```bash
sudo ss -tulpn
```

Useful for applications expected to listen on TCP or UDP ports.

This command was **not an appropriate functional test for `noc-app`**, because the training application does not provide a network service.

General options:

```text
-t    TCP
-u    UDP
-l    listening sockets
-p    process information
-n    numeric addresses/ports
```

---

## Trace live system calls

```bash
sudo strace -p <PID>
```

Attaches to a process and displays its system calls.

Useful for determining whether a process is:

* reading files,
* writing files,
* waiting,
* opening resources,
* communicating with the kernel,
* or potentially hanging.

Use carefully on production systems because tracing can affect application behavior/performance.

---

# 7. Service State Is Not Application Health

A critical operational lesson from this lab:

```text
systemctl status
       │
       ▼
SERVICE STATE
"Does systemd have a running process?"
       │
       ▼
ps / pgrep
       │
       ▼
PROCESS STATE
"Does the process actually exist?"
       │
       ▼
Application-specific test
       │
       ▼
APPLICATION STATE
"Is the process accomplishing its intended work?"
```

An application showing:

```text
Active: active (running)
```

is not necessarily healthy.

For this application, its job is to write a log entry every 10 seconds.

Therefore, functional verification is:

```bash
sudo tail /var/log/noc-app.log
```

Live verification:

```bash
sudo tail -f /var/log/noc-app.log
```

Expected:

```text
Mon Aug 17 05:10:25 PM UTC 2026 - NOC application running
Mon Aug 17 05:10:35 PM UTC 2026 - NOC application running
Mon Aug 17 05:10:45 PM UTC 2026 - NOC application running
```

The continuously advancing timestamps prove that the application workload is functioning.

---

# 8. Automatic Recovery Testing

## Graceful termination test

The original process was identified:

```bash
ps -ef | grep '[n]oc-app'
```

PID:

```text
4132
```

The process was terminated:

```bash
sudo kill 4132
```

Plain `kill` sends `SIGTERM` by default.

Systemd reported:

```text
noc-app.service: Deactivated successfully.
```

The service remained:

```text
inactive (dead)
```

Systemd therefore did not apply the `Restart=on-failure` policy because the termination was considered successful rather than an application failure.

---

## Forced failure test

Restart:

```bash
sudo systemctl start noc-app
```

Determine PID:

```bash
systemctl show noc-app -p MainPID
```

Result:

```text
MainPID=4933
```

Force abnormal termination:

```bash
sudo kill -9 4933
```

`-9` sends `SIGKILL`.

Unlike SIGTERM, SIGKILL cannot be handled or ignored by the application.

Systemd detected the abnormal failure and restarted the service.

Verification:

```bash
systemctl status noc-app
```

Result included:

```text
Scheduled restart job, restart counter is at 1.
Started noc-app.service - NOC Training Application.
```

New PID:

```text
MainPID=4948
```

Check restart count:

```bash
systemctl show noc-app -p MainPID -p NRestarts
```

Result:

```text
MainPID=4948
NRestarts=1
```

---

## Recovery Diagram

```text
noc-app running
PID 4933
     │
     ▼
SIGKILL
kill -9 4933
     │
     ▼
Process terminates abnormally
     │
     ▼
systemd detects failure
     │
     ▼
Restart=on-failure
     │
     ▼
systemd launches new process
     │
     ▼
PID 4948
NRestarts=1
```

---

# 9. SIGTERM vs SIGKILL

Observed behavior:

```text
SIGTERM
kill <PID>
      │
      ▼
Graceful/expected termination
      │
      ▼
systemd considered service
successfully deactivated
      │
      ▼
Restart=on-failure
did not restart it
```

Compared with:

```text
SIGKILL
kill -9 <PID>
      │
      ▼
Abnormal termination
      │
      ▼
systemd detects failure
      │
      ▼
Restart=on-failure
      │
      ▼
Service restarted
```

---

# 10. Enable Service at Boot

A service can be running while still being disabled:

```text
Loaded: loaded (...; disabled; preset: enabled)
```

Check enablement:

```bash
systemctl is-enabled noc-app
```

Enable:

```bash
sudo systemctl enable noc-app
```

Verify:

```bash
systemctl is-enabled noc-app
```

Expected:

```text
enabled
```

---

# 11. Inspect systemd Enablement

Inspect the target:

```bash
ls -l /etc/systemd/system/multi-user.target.wants/ | grep noc-app
```

Enabling the service creates a symbolic link:

```text
/etc/systemd/system/
│
├── noc-app.service
│
└── multi-user.target.wants/
      │
      └── noc-app.service
             │
             └──────────► /etc/systemd/system/noc-app.service
```

Relationship:

```text
WantedBy=multi-user.target
          │
          ▼
Defines where enablement
should hook the service
          │
          ▼
systemctl enable noc-app
          │
          ▼
Creates symlink
          │
          ▼
System reaches multi-user.target
during boot
          │
          ▼
noc-app.service starts
```

---

# 12. Start vs Enable vs Restart Policy

These concepts are independent.

```text
systemctl start noc-app
        │
        ▼
Run service NOW
```

```text
systemctl enable noc-app
        │
        ▼
Configure service for
automatic boot startup
```

```text
Restart=on-failure
        │
        ▼
Automatically recover from
qualifying runtime failures
```

A service can therefore be:

```text
active   + enabled
active   + disabled
inactive + enabled
inactive + disabled
```

---

# 13. Verify Boot Persistence

Before reboot:

```bash
systemctl is-enabled noc-app
systemctl is-active noc-app
```

Then:

```bash
sudo reboot
```

After reconnecting:

```bash
systemctl status noc-app
```

Observed:

```text
Loaded: loaded (...; enabled; preset: enabled)
Active: active (running)
Main PID: 801
```

Determine system boot time:

```bash
uptime -s
```

Observed:

```text
2026-08-17 16:03:35
```

Determine when the service became active:

```bash
systemctl show noc-app -p ActiveEnterTimestamp
```

Observed:

```text
ActiveEnterTimestamp=Mon 2026-08-17 16:03:37 UTC
```

Confirm enablement:

```bash
systemctl is-enabled noc-app
```

Result:

```text
enabled
```

The service became active **two seconds after system boot**, proving automatic startup.

---

## Boot Persistence Evidence

```text
SERVER BOOT
16:03:35
     │
     ▼
systemd startup
     │
     ▼
multi-user.target
     │
     ▼
noc-app.service enabled
     │
     ▼
SERVICE ACTIVE
16:03:37
     │
     ▼
Main PID 801
```

---

# 14. Incident INC-LNX-006

## Scenario

Monitoring reports:

```text
INCIDENT: INC-LNX-006
HOST:     devops02
SERVICE:  noc-app.service
SEVERITY: High

ALERT:
NOC Training Application unavailable.
```

Expected behavior:

* `noc-app.service` active.
* Application continuously writes to `/var/log/noc-app.log`.

---

# 15. Injected Failure

The working unit contained:

```ini
ExecStart=/opt/noc-lab/noc-app.sh
```

It was deliberately changed to:

```ini
ExecStart=/opt/noc-lab/noc-app-prod.sh
```

The file:

```text
/opt/noc-lab/noc-app-prod.sh
```

did not exist.

Systemd configuration was reloaded:

```bash
sudo systemctl daemon-reload
```

Service restart attempted:

```bash
sudo systemctl restart noc-app
```

---

# 16. Incident Investigation

Check service:

```bash
systemctl status noc-app
```

Observed:

```text
Active: failed (Result: exit-code)
```

and:

```text
ExecStart=/opt/noc-lab/noc-app-prod.sh
status=203/EXEC
```

---

# 17. Understanding 203/EXEC

`203/EXEC` means systemd failed to execute the process specified by `ExecStart=`.

This should trigger investigation of:

* Incorrect executable path
* Missing executable
* File permissions
* Invalid executable
* Other conditions preventing execution

Diagnostic flow:

```text
APPLICATION UNAVAILABLE
        │
        ▼
systemctl status
        │
        ▼
Active: failed
        │
        ▼
status=203/EXEC
        │
        ▼
systemd could not execute ExecStart
        │
        ▼
Inspect ExecStart
```

---

# 18. Prove the Root Cause

Inspect the unit:

```bash
cat /etc/systemd/system/noc-app.service
```

Observed:

```ini
[Service]
Type=simple
ExecStart=/opt/noc-lab/noc-app-prod.sh
Restart=on-failure
```

The filesystem was inspected and confirmed that:

```text
/opt/noc-lab/noc-app-prod.sh
```

did not exist.

The valid application was:

```text
/opt/noc-lab/noc-app.sh
```

---

## RCA Evidence Chain

```text
SYMPTOM
noc-app unavailable
       │
       ▼
SERVICE STATE
failed
       │
       ▼
FAILURE TYPE
203/EXEC
       │
       ▼
CONFIGURATION
ExecStart=/opt/noc-lab/noc-app-prod.sh
       │
       ▼
FILESYSTEM VALIDATION
noc-app-prod.sh does not exist
       │
       ▼
ROOT CAUSE
Invalid ExecStart path
```

---

# 19. Automatic Restart Rate Limiting

Because the unit contained:

```ini
Restart=on-failure
```

systemd repeatedly attempted to restart the failed application.

The journal/status eventually reported:

```text
Scheduled restart job, restart counter is at 5.
Start request repeated too quickly.
Failed with result 'exit-code'.
```

Workflow:

```text
Bad configuration
       │
       ▼
Start fails
       │
       ▼
Restart=on-failure
       │
       ▼
Restart attempt
       │
       ▼
Same configuration error
       │
       ▼
Failure again
       │
       ▼
Repeated failures
       │
       ▼
systemd rate limiting
       │
       ▼
Start request repeated too quickly
       │
       ▼
SERVICE FAILED
```

### Operational Lesson

**Automatic restart is recovery, not repair.**

A transient process failure may be corrected by restarting.

A persistent configuration problem will continue failing until the underlying cause is corrected.

---

# 20. Remediation

Correct:

```ini
ExecStart=/opt/noc-lab/noc-app-prod.sh
```

to:

```ini
ExecStart=/opt/noc-lab/noc-app.sh
```

After changing a systemd unit file:

```bash
sudo systemctl daemon-reload
```

This instructs systemd to reread unit configuration from disk.

Without it, systemd may continue operating with its previously loaded configuration.

Restart:

```bash
sudo systemctl restart noc-app
```

Verify:

```bash
systemctl status noc-app
```

Observed:

```text
Active: active (running)
Main PID: 8402
```

---

# 21. Post-Remediation Functional Verification

Service state alone was not considered sufficient evidence.

Verify application output:

```bash
sudo tail -n 5 /var/log/noc-app.log
```

Observed:

```text
05:10:25 PM UTC 2026 - NOC application running
05:10:35 PM UTC 2026 - NOC application running
05:10:45 PM UTC 2026 - NOC application running
05:10:55 PM UTC 2026 - NOC application running
05:11:05 PM UTC 2026 - NOC application running
```

The 10-second intervals match the application's intended workload.

Therefore:

```text
Configuration corrected
       │
       ▼
daemon-reload
       │
       ▼
service restarted
       │
       ▼
systemctl = active
       │
       ▼
process exists
       │
       ▼
application log advances
every 10 seconds
       │
       ▼
SERVICE FUNCTIONALLY RESTORED
```

---

# 22. Journal Investigation

View logs for a service:

```bash
journalctl -u noc-app
```

`-u` restricts output to the specified systemd unit.

Limit by time:

```bash
journalctl -u noc-app --since "2 minutes ago"
```

Other examples:

```bash
journalctl -u noc-app --since "10 minutes ago"
journalctl -u noc-app --since "30 minutes ago"
```

The argument to `--since` is required.

This is invalid:

```bash
journalctl -u noc-app --since
```

and returns:

```text
option '--since' requires an argument
```

---

# 23. Pre-Deployment Unit Validation

Use:

```bash
systemd-analyze verify /etc/systemd/system/noc-app.service
```

Purpose:

Validate a systemd unit and report detected configuration problems before deployment/restart.

A valid unit may produce **no terminal output**.

Immediately check the exit status:

```bash
echo $?
```

Linux convention:

```text
0          success
non-zero   failure/error condition
```

Validation workflow:

```text
Proposed unit change
        │
        ▼
systemd-analyze verify
        │
        ▼
      Valid?
     /      \
   NO        YES
   │          │
   ▼          ▼
DO NOT     daemon-reload
DEPLOY         │
   │           ▼
Correct      restart
configuration  │
               ▼
             verify
               │
               ▼
        Functional test
```

### Important Limitation

Unit validation does not eliminate the need for functional testing.

A unit may be structurally valid while still containing an operationally incorrect value.

Always perform both:

```text
CONFIGURATION VALIDATION
          +
SERVICE VERIFICATION
          +
APPLICATION VERIFICATION
```

---

# 24. systemd Troubleshooting Decision Tree

```text
MONITORING ALERT
Application unavailable
        │
        ▼
systemctl status <service>
        │
        ├──────── Active ──────────┐
        │                          │
        │                          ▼
        │                 Verify application
        │                 functionality
        │                          │
        │                    ┌─────┴─────┐
        │                 Healthy      Broken
        │                    │            │
        │                    ▼            ▼
        │                  CLOSE      Application-
        │                             level diagnosis
        │
        ▼
Failed / Inactive
        │
        ▼
Inspect status/error
        │
        ▼
journalctl -u <service>
        │
        ▼
Identify failure class
        │
        ├── 203/EXEC
        │       │
        │       ▼
        │   Inspect ExecStart
        │       │
        │       ▼
        │   Validate path/file/
        │   executable permissions
        │
        ├── Configuration error
        │       │
        │       ▼
        │   Inspect unit/config
        │
        └── Runtime failure
                │
                ▼
            Inspect process,
            resources and logs
                │
                ▼
          ROOT CAUSE IDENTIFIED
                │
                ▼
             Remediate
                │
                ▼
        systemctl daemon-reload
        if unit changed
                │
                ▼
             Restart
                │
                ▼
       systemctl status
                │
                ▼
       Process verification
                │
                ▼
      Functional verification
                │
                ▼
          INCIDENT CLOSED
```

---

# 25. Command Reference

| Command                                          | Purpose                                                 |
| ------------------------------------------------ | ------------------------------------------------------- |
| `systemctl status noc-app`                       | Inspect service state, PID and recent systemd messages  |
| `systemctl start noc-app`                        | Start service immediately                               |
| `systemctl restart noc-app`                      | Stop/start service                                      |
| `systemctl is-active noc-app`                    | Determine whether service is currently active           |
| `systemctl enable noc-app`                       | Configure automatic boot startup                        |
| `systemctl is-enabled noc-app`                   | Check boot enablement                                   |
| `systemctl --failed`                             | List failed systemd units                               |
| `systemctl cat noc-app`                          | Display systemd's unit definition                       |
| `systemctl show noc-app -p MainPID`              | Obtain service Main PID                                 |
| `systemctl show noc-app -p NRestarts`            | Display automatic restart count                         |
| `systemctl show noc-app -p Restart`              | Display configured restart policy                       |
| `systemctl show noc-app -p ActiveEnterTimestamp` | Show when service entered active state                  |
| `systemctl daemon-reload`                        | Reload systemd unit definitions after unit-file changes |
| `journalctl -u noc-app`                          | Display journal entries for the service                 |
| `journalctl -u noc-app --since "10 minutes ago"` | Display recent service journal entries                  |
| `pgrep -a noc-app`                               | Find matching process and display command               |
| `ps -ef`                                         | Display full-format process listing                     |
| `lsof -p <PID>`                                  | Display resources opened by a process                   |
| `ss -tulpn`                                      | Display listening TCP/UDP sockets and owning processes  |
| `strace -p <PID>`                                | Observe live system calls from a process                |
| `kill <PID>`                                     | Send SIGTERM to a process                               |
| `kill -9 <PID>`                                  | Send uncatchable SIGKILL                                |
| `tail <file>`                                    | Display recent lines from a file                        |
| `tail -f <file>`                                 | Follow new file output in real time                     |
| `uptime -s`                                      | Display system boot timestamp                           |
| `systemd-analyze verify <unit>`                  | Validate a systemd unit                                 |
| `echo $?`                                        | Display exit status of immediately preceding command    |
| `man systemd-analyze`                            | Read systemd-analyze documentation                      |

---

# 26. Incident Closure — INC-LNX-006

**Symptom:**
`noc-app` unavailable.

**Impact:**
Application workload stopped.

**Service state:**
`failed`

**Error:**
`203/EXEC`

**Investigation:**
`systemctl status` identified failure executing `ExecStart`.

**Configuration discovered:**

```text
ExecStart=/opt/noc-lab/noc-app-prod.sh
```

**Filesystem validation:**
Configured executable did not exist.

**Root cause:**
Incorrect executable path configured in the systemd unit.

**Remediation:**
Changed `ExecStart` to:

```text
/opt/noc-lab/noc-app.sh
```

Reloaded systemd:

```bash
sudo systemctl daemon-reload
```

Restarted service:

```bash
sudo systemctl restart noc-app
```

**Service verification:**

```text
Active: active (running)
```

**Functional verification:**
`/var/log/noc-app.log` resumed receiving entries every 10 seconds.

**Final status:**

```text
RESOLVED
```

---

# 27. Key Lessons

1. **A running service does not necessarily mean a healthy application.**

2. Use application-specific validation after checking `systemctl`.

3. `ExecStart=` determines what systemd executes.

4. `Restart=on-failure` provides recovery from qualifying failures but does not repair persistent configuration problems.

5. `WantedBy=multi-user.target` participates in boot enablement; it is not an access-control directive.

6. `systemctl start` and `systemctl enable` perform different administrative functions.

7. `203/EXEC` should immediately focus investigation on execution of the configured `ExecStart` command.

8. Editing a unit file requires:

```bash
sudo systemctl daemon-reload
```

before relying on the new configuration.

9. `journalctl -u` is a primary diagnostic tool for systemd-managed workloads.

10. Systemd rate limiting can stop repeated restart attempts when a persistent fault prevents recovery.

11. Validate configuration before deployment with:

```bash
systemd-analyze verify
```

12. After remediation, verify at three levels:

```text
SERVICE
   ↓
PROCESS
   ↓
APPLICATION FUNCTION
```

13. Root-cause analysis should be based on evidence rather than simply restarting a failed service.

---

# 28. L2 NOC Operational Workflow

```text
ALERT
  │
  ▼
Validate impact
  │
  ▼
Check service state
  │
  ▼
Collect logs/errors
  │
  ▼
Classify failure
  │
  ▼
Determine root cause
  │
  ▼
Apply remediation
  │
  ▼
Restore service
  │
  ▼
Verify process
  │
  ▼
Verify application function
  │
  ▼
Monitor stability
  │
  ▼
Document RCA/evidence
  │
  ▼
CLOSE INCIDENT
```

---

## Lab Status

**Lab:** Linux Administration Lab #006
**Topic:** systemd Service Administration & Troubleshooting
**Status:** COMPLETE
**Incident:** INC-LNX-006 — RESOLVED

### Skills Demonstrated

* Linux service administration
* systemd unit creation
* Process inspection
* Service monitoring
* Boot persistence
* Automatic service recovery
* Linux signal handling
* Journal analysis
* Failure-code interpretation
* `203/EXEC` troubleshooting
* Configuration validation
* Root-cause analysis
* Incident remediation
* Functional service verification
* L2 incident ownership

---

## Suggested Git Commit

```bash
git add .
git commit -m "Add RB-0006 systemd service administration and troubleshooting lab"
```

