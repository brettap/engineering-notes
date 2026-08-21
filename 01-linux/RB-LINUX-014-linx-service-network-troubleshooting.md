# RB-LINUX-014 — Linux Service and Network Troubleshooting

## Purpose

Establish a repeatable troubleshooting workflow for investigating reports that a Linux-hosted application or service is unreachable.

This runbook focuses on determining whether a reported outage originates from:

* Host availability
* systemd service state
* Application process state
* Network socket/listener state
* Local application connectivity
* Remote client connectivity
* Linux firewall configuration
* Web server configuration
* Application deployment/configuration
* Incorrect or incomplete incident information

The objective is to troubleshoot from evidence rather than assumptions.

---

## Environment

| Component              | Value                     |
| ---------------------- | ------------------------- |
| Host                   | `devops02`                |
| IP Address             | `192.168.1.137`           |
| Operating System       | Ubuntu Linux              |
| SSH Service            | OpenSSH                   |
| Web Server             | Nginx                     |
| Training Service       | `noc-app.service`         |
| NOC Application Script | `/opt/noc-lab/noc-app.sh` |
| NOC Application Log    | `/var/log/noc-app.log`    |
| Nginx Document Root    | `/var/www/html`           |
| Client Test Host       | `192.168.1.103`           |
| Firewall               | UFW                       |

---

# Incident Scenario

An incident was reported stating:

> Application service on `devops02` is unreachable.

The initial report did not specify:

* Application name
* URL
* Port
* Expected response
* Scope of impact
* Last known working state

The investigation therefore began by establishing the server's current state.

---

# Troubleshooting Workflow

```text
INCIDENT REPORTED
       |
       v
What exactly is affected?
       |
       v
What is the expected behavior?
       |
       v
What is the observed behavior?
       |
       v
What host/service/application owns it?
       |
       v
Establish scope
       |
       v
Reproduce / verify
       |
       v
Host
       |
       v
Process
       |
       v
Service
       |
       v
Socket
       |
       v
Local connectivity
       |
       v
Remote connectivity
       |
       v
Application response
       |
       v
Logs / configuration
       |
       v
ROOT CAUSE
       |
       v
REMEDIATE
       |
       v
VERIFY
       |
       v
DOCUMENT
```

---

# 1. Verify Host Availability

Connected to `devops02` successfully through SSH.

```bash
hostname
```

Output:

```text
devops02
```

SSH was confirmed operational:

```bash
systemctl status ssh
```

Relevant result:

```text
Active: active (running)
```

### Finding

The server was reachable and SSH administration was available.

Host availability was therefore eliminated as the immediate cause.

---

# 2. Check for Failed systemd Services

```bash
systemctl --failed
```

Result:

```text
0 loaded units listed.
```

### Finding

systemd did not report any failed units.

Important distinction:

```text
No failed systemd units
        !=
Application is healthy
```

A service may remain `active (running)` even when the application it represents is malfunctioning.

---

# 3. Identify Running Services

```bash
systemctl list-units --type=service --state=running
```

Relevant services included:

```text
nginx.service
noc-app.service
ssh.service
docker.service
containerd.service
```

Two services appeared potentially relevant to the reported application outage:

```text
noc-app.service
nginx.service
```

---

# 4. Investigate the NOC Application Service

Checked the service:

```bash
systemctl status noc-app.service --no-pager
```

Result:

```text
Active: active (running)
Main PID: 856
```

The process was:

```text
/bin/bash /opt/noc-lab/noc-app.sh
```

---

# 5. Inspect the systemd Unit Definition

```bash
systemctl cat noc-app.service
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

### Finding

systemd starts:

```text
/opt/noc-lab/noc-app.sh
```

The next step was therefore to inspect the executable rather than assume what the service did.

---

# 6. Inspect the Running Process

```bash
ps -fp $(systemctl show -p MainPID --value noc-app.service)
```

Result:

```text
UID   PID  PPID  CMD
root  856     1  /bin/bash /opt/noc-lab/noc-app.sh
```

### Finding

The service was running as a Bash script under systemd.

---

# 7. Inspect the Application Script

```bash
cat /opt/noc-lab/noc-app.sh
```

Contents:

```bash
#!/bin/bash

while true
do
    echo "$(date) - NOC application running" >> /var/log/noc-app.log
    sleep 10
done
```

### Finding

`noc-app.service` was not a network application.

Its only function was to:

1. Write a timestamp to `/var/log/noc-app.log`
2. Sleep for 10 seconds
3. Repeat indefinitely

The service does not open a network socket.

---

# 8. Verify Whether noc-app Owns a Network Listener

```bash
sudo ss -tulpn | grep -E 'pid=856|noc-app'
```

Result:

```text
No output
```

### Finding

No TCP or UDP listener belonged to `noc-app`.

This was expected based on the script implementation.

---

# 9. Inspect Listening Network Sockets

```bash
sudo ss -tulpn
```

Relevant listeners included:

```text
0.0.0.0:80
0.0.0.0:22
*:9100
```

Interpretation:

```text
TCP/22    SSH
TCP/80    HTTP / Nginx
TCP/9100  Monitoring / Node Exporter
```

Nginx was therefore the primary network-facing service associated with HTTP traffic.

---

# 10. Understand Listener Bind Addresses

Nginx was listening on:

```text
0.0.0.0:80
```

`0.0.0.0` means the application is listening on all IPv4 interfaces.

Therefore Nginx should accept connections through:

```text
127.0.0.1:80
192.168.1.137:80
```

assuming routing and firewall policy permit the traffic.

---

# 11. Inspect UFW

```bash
sudo ufw status
```

Relevant rules:

```text
Nginx HTTP    ALLOW    Anywhere
22/tcp        ALLOW    192.168.1.0/24
Nginx HTTP (v6) ALLOW  Anywhere (v6)
```

### Finding

UFW appeared to permit inbound HTTP traffic.

However, configuration was not treated as proof of connectivity.

The actual network path still needed testing.

---

# 12. Inspect Nginx Service State

```bash
systemctl status nginx --no-pager
```

Result:

```text
Active: active (running)
```

Nginx master and worker processes were present.

### Finding

The Nginx process was operational.

---

# 13. Validate Nginx Configuration

```bash
sudo nginx -T
```

Relevant result:

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

The enabled default site contained:

```nginx
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;

        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
                try_files $uri $uri/ =404;
        }
}
```

### Finding

Nginx:

* Was configured correctly
* Listened on TCP/80
* Served `/var/www/html`
* Used the default Ubuntu Nginx site

---

# 14. Test HTTP Locally

Test from `devops02`:

```bash
curl -v http://127.0.0.1/
```

Relevant response:

```text
Connected to 127.0.0.1 port 80
HTTP/1.1 200 OK
Server: nginx/1.24.0
```

Returned page:

```text
Welcome to nginx!
```

### Finding

The local TCP/IP stack, Nginx listener, HTTP service, and document serving path were functional.

---

# 15. Test HTTP Remotely

A Windows client at `192.168.1.103` tested:

```powershell
curl -v http://192.168.1.137
```

PowerShell returned:

```text
StatusCode        : 200
StatusDescription : OK
```

### Finding

The complete remote path was functional:

```text
Windows Client
192.168.1.103
      |
      | TCP/80
      v
Network
      |
      v
UFW
      |
      v
DevOps02
192.168.1.137
      |
      v
Nginx
      |
      v
HTTP 200 OK
```

This eliminated:

* Basic routing failure
* UFW HTTP blockage
* TCP/80 listener failure
* Nginx process failure
* Nginx local-only binding
* Basic client-to-server connectivity failure

---

# 16. Validate the Application-Layer Response

Although HTTP returned:

```text
200 OK
```

the returned application content was:

```text
Welcome to nginx!
```

This was the default web server page.

### Important Lesson

```text
HTTP 200
   !=
Correct application
```

A successful HTTP response proves the web server responded.

It does not prove the expected application was deployed or healthy.

---

# 17. Inspect Nginx Web Content

```bash
cd /var/www/html
```

The default page was inspected:

```bash
cat index.nginx-debian.html
```

The page contained:

```text
Welcome to nginx!
```

### Finding

Nginx was correctly serving its standard Ubuntu default page.

No custom NOC web application was present.

---

# 18. Inspect the NOC Workload Directory

```bash
cd /opt/noc-lab
```

```bash
ls
```

Contents:

```text
log-generator.sh
noc-app.sh
storage-lab.img
```

### Finding

The NOC workload consisted of:

* Logging workload
* Log generation script
* Storage lab image

No network-facing application was deployed.

---

# 19. Verify noc-app Runtime Activity

```bash
tail -n 20 /var/log/noc-app.log
```

Example output:

```text
Fri Aug 21 08:28:08 PM UTC 2026 - NOC application running
Fri Aug 21 08:28:18 PM UTC 2026 - NOC application running
Fri Aug 21 08:28:28 PM UTC 2026 - NOC application running
Fri Aug 21 08:28:38 PM UTC 2026 - NOC application running
```

### Finding

`noc-app.service` was performing its intended function correctly.

The process was alive and continuously writing log entries every 10 seconds.

---

# Root Cause / Incident Determination

No Linux service outage was identified.

The reported incident stated that an "application service" was unreachable, but investigation determined:

```text
noc-app.service
      |
      v
Active and healthy
      |
      v
Writes log data
      |
      v
Does not provide network service
```

Meanwhile:

```text
Nginx
   |
   v
Active
   |
   v
Listening TCP/80
   |
   v
Reachable locally
   |
   v
Reachable remotely
   |
   v
HTTP 200
   |
   v
Serving default Nginx page
```

No deployed network application corresponding to the original incident description was identified.

The incident therefore lacked sufficient application identification and environment context.

---

# Correct Operational Response

A suitable technical update would be:

> Host and Nginx connectivity are healthy. TCP/80 is reachable remotely and returns HTTP 200. `noc-app.service` is active; however, inspection shows that it is a logging workload and does not expose a network endpoint. No deployed network application matching the reported outage has been identified. Additional information is required identifying the affected service, URL, port, or expected application behavior.

---

# Lessons Learned

## 1. Do Not Trust the Incident Description as a Diagnosis

An incident may report:

```text
Application is down
```

but that statement does not establish:

* What application
* What server
* What port
* What component
* What failure domain

Treat the report as the beginning of the investigation.

---

## 2. Establish Scope Before Remediation

Useful incident questions include:

```text
What exactly is affected?

What is the expected behavior?

What behavior are you observing?

What hostname or application owns the service?

What URL or port is involved?

Who is affected?

When did it last work?

Can the failure be reproduced?
```

---

## 3. Engineers Can Provide Ambiguous Information Too

Technical terminology does not automatically make an incident report precise.

Examples:

```text
"The API is down."

"Authentication is broken."

"The server isn't responding."

"DNS is messed up."

"Bounce the service."
```

These may be observations, assumptions, or proposed diagnoses.

They still require verification.

---

## 4. Institutional Knowledge Creates Missing Context

Engineers familiar with an environment may assume others understand:

* Internal application names
* Server roles
* Service dependencies
* Port assignments
* Architecture
* Internal terminology

An administrator entering an unfamiliar environment must establish that missing context rather than pretend it is known.

---

## 5. Verify Engineer Diagnoses Before Changing Systems

Example:

```text
Engineer says:
"UFW is blocking the application."
          |
          v
Do not immediately modify firewall rules.
          |
          v
Verify:
process
service
listener
bind address
local connection
remote connection
firewall
```

Configuration changes should follow evidence.

---

## 6. systemd State Is Only One Layer

```text
systemctl status
```

may report:

```text
active (running)
```

while the application itself could still be:

* Hung
* Misconfigured
* Listening on the wrong port
* Bound only to loopback
* Returning application errors
* Unable to reach a dependency
* Serving incorrect content

---

## 7. A Running Process Does Not Imply a Network Service

The `noc-app` process was healthy but opened no network socket.

Understanding what a process actually does is necessary before troubleshooting network connectivity for it.

---

## 8. HTTP 200 Does Not Prove Application Health

An HTTP 200 response confirms successful HTTP processing.

It does not necessarily confirm:

```text
Correct application
Correct data
Correct backend
Correct authentication
Correct dependencies
Correct business function
```

In this incident, HTTP 200 returned only the default Nginx page.

---

# Diagnostic Model

Use the following model when troubleshooting application availability:

```text
USER / MONITORING ALERT
          |
          v
IDENTIFY THE ACTUAL SERVICE
          |
          v
HOST REACHABILITY
          |
          v
SYSTEMD SERVICE
          |
          v
PROCESS
          |
          v
SOCKET / PORT
          |
          v
BIND ADDRESS
          |
          v
LOCAL TEST
          |
          v
REMOTE TEST
          |
          v
FIREWALL / ROUTING
          |
          v
APPLICATION-LAYER RESPONSE
          |
          v
LOGS / CONFIGURATION
          |
          v
DEPENDENCIES
          |
          v
ROOT CAUSE
```

---

# Future Environment Improvement

The current `noc-app` is a workload simulator rather than a true network application.

A future lab should deploy a small networked NOC application using an architecture such as:

```text
systemd
   |
   v
Application Service
   |
   | localhost:<application-port>
   v
Nginx Reverse Proxy
   |
   | TCP/80
   v
UFW
   |
   v
Network
   |
   v
Clients / Monitoring
```

This architecture will allow future blind incidents involving:

* Application process failure
* systemd failures
* Incorrect ports
* Incorrect bind addresses
* Nginx upstream failures
* Firewall rules
* Permissions
* Configuration drift
* Disk exhaustion
* CPU or memory exhaustion
* DNS problems
* Logging failures
* Monitoring failures

---

# Future Tooling Project — Lay-of-the-Land Scripts

Develop two baseline-discovery tools:

```text
lay-of-the-land.sh
lay-of-the-land.ps1
```

Purpose:

Allow an administrator entering an unfamiliar Linux or Windows server to quickly establish:

* Host identity
* Operating system
* IP configuration
* DNS configuration
* Routing
* CPU and memory
* Storage/filesystems
* Running services
* Failed services
* Running processes
* Listening ports
* Process-to-port relationships
* Firewall state
* Scheduled tasks/jobs
* Installed server roles
* Containers
* Application directories
* Mounted shares
* Logging configuration
* Monitoring agents
* Recent system errors
* Likely server responsibilities

The scripts should assist with answering:

> What is this server responsible for?

before performing changes.

---

# Command Reference

## `hostname`

```bash
hostname
```

Displays the current system hostname.

Useful for confirming that the administrator is connected to the intended host.

---

## `systemctl status`

```bash
systemctl status <service>
```

Displays detailed service state including:

* Loaded state
* Active state
* Main PID
* Child processes
* Recent journal entries

Example:

```bash
systemctl status nginx --no-pager
```

`--no-pager` prints output directly rather than opening the pager.

---

## `systemctl --failed`

```bash
systemctl --failed
```

Lists systemd units currently in a failed state.

A clean result does not guarantee application health.

---

## `systemctl list-units`

```bash
systemctl list-units --type=service --state=running
```

Lists currently running systemd services.

Options:

```text
--type=service
```

Limits output to service units.

```text
--state=running
```

Limits output to active running services.

---

## `systemctl cat`

```bash
systemctl cat <service>
```

Displays the systemd unit configuration associated with a service.

Useful for identifying:

* `ExecStart`
* Dependencies
* Restart behavior
* Service type
* Environment files

---

## `systemctl show`

```bash
systemctl show -p MainPID --value <service>
```

Displays the main process ID associated with a systemd service.

Options:

```text
-p MainPID
```

Requests only the `MainPID` property.

```text
--value
```

Returns only the value rather than the property name.

---

## `ps`

```bash
ps -fp <PID>
```

Displays process information.

Options:

```text
-f
```

Full-format output.

```text
-p
```

Select a process by PID.

Combined example:

```bash
ps -fp $(systemctl show -p MainPID --value noc-app.service)
```

Maps a systemd service directly to its process.

---

## `cat`

```bash
cat <file>
```

Displays file contents.

Examples:

```bash
cat /opt/noc-lab/noc-app.sh
```

```bash
cat /var/www/html/index.nginx-debian.html
```

Useful for inspecting scripts and configuration/content files.

---

## `ss`

```bash
sudo ss -tulpn
```

Displays network sockets.

Options:

```text
-t   TCP sockets
-u   UDP sockets
-l   Listening sockets
-p   Associated process
-n   Numeric IP addresses and ports
```

Useful for answering:

```text
What is listening?
On which port?
On which interface?
Which process owns the socket?
```

Example filter:

```bash
sudo ss -tulpn | grep -E 'pid=856|noc-app'
```

---

## `grep`

```bash
grep -E '<pattern>'
```

Searches text for matching patterns.

`-E` enables extended regular expressions.

Example:

```bash
sudo ss -tulpn | grep -E 'pid=856|noc-app'
```

---

## `ufw status`

```bash
sudo ufw status
```

Displays Uncomplicated Firewall status and configured rules.

Useful for determining whether required inbound ports appear to be permitted.

Firewall configuration should still be validated using actual connectivity tests.

---

## `nginx -T`

```bash
sudo nginx -T
```

Tests Nginx configuration syntax and prints the complete active configuration.

Useful for identifying:

* Listen ports
* Server blocks
* Document roots
* Reverse proxies
* Included configuration files

---

## `curl`

```bash
curl -v http://127.0.0.1/
```

Performs an HTTP request.

`-v` enables verbose output showing:

* TCP connection establishment
* HTTP request headers
* HTTP response headers
* Response status

Local test:

```bash
curl -v http://127.0.0.1/
```

Remote test:

```bash
curl -v http://192.168.1.137/
```

---

## PowerShell `curl`

In Windows PowerShell:

```powershell
curl http://192.168.1.137
```

may resolve to:

```powershell
Invoke-WebRequest
```

rather than the native `curl.exe`.

The response includes information such as:

```text
StatusCode
StatusDescription
Headers
Content
```

A native curl request can be explicitly invoked with:

```powershell
curl.exe -v http://192.168.1.137
```

---

## `ls`

```bash
ls
```

Lists directory contents.

Example:

```bash
ls /opt/noc-lab
```

Useful for discovering application files and deployment structure.

---

## `tail`

```bash
tail -n 20 <file>
```

Displays the final 20 lines of a file.

Example:

```bash
tail -n 20 /var/log/noc-app.log
```

Useful for quickly reviewing recent application or system log activity.

---

# Final Outcome

The investigation successfully demonstrated a layered Linux application troubleshooting workflow.

No outage was found in the deployed services.

Instead, the investigation identified that the original incident report did not correspond to an actual network application deployed on the server.

The lab demonstrated the operational principle:

```text
Do not troubleshoot the description.

Troubleshoot the evidence.
```

## Status

**RB-LINUX-014: COMPLETE**
