# RB-LINUX-002 — Nginx Installation and systemd Service Management

**Lab:** Linux Administration Lab #002  
**Ticket:** SR-2001 — Install Web Service  
**System:** DevOps02  
**IP:** `192.168.1.137`  
**OS:** Ubuntu Linux  
**Service:** nginx  
**Status:** COMPLETE / VERIFIED

---

## 1. Objective

Install and configure nginx as a native Ubuntu service on DevOps02.

Acceptance criteria:

- nginx installed from Ubuntu repositories
- nginx service running
- nginx configured to start automatically at boot
- TCP port 80 listening
- HTTP service responds successfully
- Default nginx page accessible

---

# 2. Architecture

```text
                Windows Workstation
                        │
                        │ HTTP
                        ▼
              http://192.168.1.137
                        │
                        │ TCP/80
                        ▼
                ┌───────────────┐
                │   DevOps02    │
                │ 192.168.1.137 │
                │               │
                │     nginx     │
                │       │       │
                │   systemd     │
                └───────────────┘
```

This reinforced an important point:

**nginx is not a separate network endpoint.**

It is an application running on DevOps02, so the service is reached through **DevOps02's IP address** and nginx's listening port.

```text
Server:       DevOps02
IP:           192.168.1.137
Application:  nginx
Protocol:     HTTP
Port:         TCP/80

Result:
http://192.168.1.137
```

---

# 3. Install nginx

nginx was installed using Ubuntu's standard APT package-management system.

```bash
sudo apt update
sudo apt install nginx
```

This satisfies the requirement that the application be installed from the operating system's normal package repository rather than Docker or another deployment mechanism.

---

# 4. Check nginx Service Status

nginx is managed by `systemd`.

Check its state:

```bash
systemctl status nginx
```

Expected operational state:

```text
Active: active (running)
```

This establishes that the service is currently running.

---

# 5. systemd Service Concepts

An important distinction was reinforced during the lab:

```text
systemctl start nginx
        │
        ▼
Run nginx NOW


systemctl enable nginx
        │
        ▼
Configure nginx to start at BOOT


systemctl enable --now nginx
        │
        ├── enable at boot
        └── start immediately
```

These are separate states.

A service can therefore potentially be:

```text
RUNNING + DISABLED
```

or:

```text
STOPPED + ENABLED
```

Checking that a process is running does not prove that it will return after reboot.

---

# 6. Configure nginx to Start Automatically

Initial attempt:

```bash
sudo chkconfig nginx
```

Result:

```text
command not found
```

## Why

`chkconfig` belongs to older SysV-style service-management environments and is not the normal mechanism for managing modern Ubuntu `systemd` services.

The appropriate systemd mechanism is:

```bash
sudo systemctl enable nginx
```

Verify:

```bash
systemctl is-enabled nginx
```

Expected:

```text
enabled
```

---

# 7. Verify Listening Port

The listening sockets were inspected with:

```bash
ss -tuln
```

Useful options:

```text
-t    TCP sockets
-u    UDP sockets
-l    listening sockets
-n    numeric addresses/ports
```

For more useful process information:

```bash
sudo ss -tulnp
```

To specifically investigate port 80:

```bash
sudo ss -tulnp | grep :80
```

This allows us to establish:

```text
nginx
   │
   ▼
TCP :80
   │
   ▼
LISTENING
```

rather than merely assuming nginx is available because `systemctl` reports that the service is running.

---

# 8. Test HTTP Locally with curl

The command initially forgotten during the exercise was:

```bash
curl http://localhost
```

Because the request originates on DevOps02 itself:

```text
DevOps02
   │
   │ curl http://localhost
   ▼
Loopback interface
   │
   ▼
TCP :80
   │
   ▼
nginx
   │
   ▼
HTTP response
```

This returned the nginx default web content and established that nginx was actually serving HTTP.

---

# 9. Test HTTP Headers

A useful diagnostic variation is:

```bash
curl -I http://localhost
```

The `-I` option retrieves HTTP response headers rather than the complete page body.

A successful response should contain information similar to:

```text
HTTP/1.1 200 OK
Server: nginx
```

This provides a fast CLI verification that the HTTP service is responding.

---

# 10. Test from Another Device

nginx was also accessible using DevOps02's network address:

```text
http://192.168.1.137
```

Architecture:

```text
Client
  │
  │ HTTP request
  ▼
192.168.1.137
  │
  ▼
DevOps02 network stack
  │
  ▼
TCP port 80
  │
  ▼
nginx
  │
  ▼
Default nginx webpage
```

This tests more than `curl localhost`.

A local test proves:

```text
nginx → HTTP stack works locally
```

A remote test additionally exercises:

```text
Client
  ↓
Network
  ↓
DevOps02 NIC
  ↓
Host networking/firewall
  ↓
TCP :80
  ↓
nginx
```

---

# 11. Verification Matrix

| Requirement | Verification | Result |
|---|---|---|
| nginx installed | APT/package state | PASS |
| nginx running | `systemctl status nginx` | PASS |
| Starts at boot | `systemctl is-enabled nginx` | PASS |
| TCP/80 listening | `ss -tuln` / `ss -tulnp` | PASS |
| Local HTTP response | `curl http://localhost` | PASS |
| Remote HTTP access | `http://192.168.1.137` | PASS |

**SR-2001: CLOSED**

---

# 12. Troubleshooting Encountered

## Issue 1 — `chkconfig` Not Found

Attempt:

```bash
sudo chkconfig nginx
```

Result:

```text
command not found
```

### Root Cause

The system uses `systemd`; `chkconfig` was not the applicable service-management mechanism.

### Resolution

Use:

```bash
sudo systemctl enable nginx
```

Verify:

```bash
systemctl is-enabled nginx
```

---

## Issue 2 — Forgot How to Test nginx Webpage

The service was:

```text
installed
running
listening on TCP/80
```

but the HTTP test method was initially forgotten.

### Resolution

Local test:

```bash
curl http://localhost
```

Remote test:

```text
http://192.168.1.137
```

### Lesson

Remember the service relationship:

```text
HOST
DevOps02
192.168.1.137
     │
     ├── SSH ........ TCP/22
     ├── nginx ...... TCP/80
     └── future app . TCP/5000
```

Applications running on a server generally use the **server's network addresses plus their respective ports** unless networking has been configured otherwise.

---

# 13. Useful Command Reference

```bash
# Update package metadata
sudo apt update

# Install nginx
sudo apt install nginx

# Check service
systemctl status nginx

# Start service
sudo systemctl start nginx

# Stop service
sudo systemctl stop nginx

# Restart service
sudo systemctl restart nginx

# Reload configuration where supported
sudo systemctl reload nginx

# Enable at boot
sudo systemctl enable nginx

# Disable automatic startup
sudo systemctl disable nginx

# Determine boot configuration
systemctl is-enabled nginx

# Determine whether service is currently running
systemctl is-active nginx

# Enable and immediately start
sudo systemctl enable --now nginx

# Show listening TCP/UDP ports
ss -tuln

# Include process information
sudo ss -tulnp

# Investigate port 80
sudo ss -tulnp | grep :80

# Test HTTP locally
curl http://localhost

# Retrieve HTTP headers
curl -I http://localhost
```

---

# 14. Operational Troubleshooting Model

A web service should not be considered healthy based on a single check.

Use layers:

```text
              WEB SERVICE INVESTIGATION

Package installed?
       │
       ▼
Service running?
       │
       ▼
systemctl status nginx
       │
       ▼
Socket listening?
       │
       ▼
ss -tulnp
       │
       ▼
Local HTTP works?
       │
       ▼
curl http://localhost
       │
       ▼
Remote HTTP works?
       │
       ▼
http://192.168.1.137
       │
       ▼
        HEALTHY
```

Each test reduces the failure domain.

For example:

```text
systemctl = running
but
port 80 = not listening
```

means something different from:

```text
port 80 = listening
curl localhost = successful
remote client = failed
```

The second scenario points investigation away from the application itself and toward networking, firewalling, routing, or client connectivity.

---

# 15. Research and Escalation Lesson

This lab also established the training workflow going forward.

Independent research remains part of the exercise because finding technical information efficiently is itself an administration skill.

However:

```text
Problem
   │
   ▼
Investigate
   │
   ├── man pages
   ├── --help
   ├── documentation
   ├── web research
   └── existing notes
   │
   ▼
Making useful progress?
   │
 ┌─┴─┐
YES  NO
 │    │
 ▼    ▼
Continue    Ask/escalate
             │
             ▼
       targeted assistance
```

The objective is **not** to spend excessive time rediscovering simple syntax.

When the concept is understood but a command or option has simply been forgotten, obtaining the command and then using, understanding, and verifying it is a rational use of training time.

More extensive independent investigation should be reserved for situations where **diagnosis itself is the skill being practiced**.

---

# 16. Key Lessons Learned

1. nginx installed through APT can be managed directly by `systemd`.

2. `systemctl start` and `systemctl enable` solve different problems.

3. A running service is not necessarily enabled at boot.

4. `chkconfig` knowledge reflects an older Linux service-management model; modern Ubuntu uses `systemd`.

5. `systemctl is-enabled` verifies boot configuration.

6. `ss` verifies whether the operating system actually has a listening socket.

7. Adding `-p` to `ss` helps associate a listening port with its process.

8. `curl` is a fundamental Linux tool for testing HTTP services.

9. `localhost` tests the service from the server itself.

10. Testing `192.168.1.137` from another device exercises additional network layers.

11. nginx is an application hosted **on DevOps02**, so it is reached through DevOps02's IP address.

12. Service health should be validated at multiple layers rather than inferred from a single successful command.

13. Efficient escalation is an operations skill: research sufficiently to understand the problem, but don't spend disproportionate time searching for simple forgotten syntax.

---

# 17. Final Architecture

```text
                  TECHWORKS LAB

              Windows Workstation
                      │
                      │ HTTP :80
                      ▼
              192.168.1.137
                DEVOPS02
          ┌───────────┴───────────┐
          │                       │
       systemd                 Network
          │                       │
          ▼                       ▼
     nginx.service           TCP :80
          │                       │
          ├── active              │
          ├── running             │
          └── enabled             │
                  \              /
                   \            /
                    ▼          ▼
                     nginx
                       │
                       ▼
                  HTTP Response
                       │
                       ▼
                Default Webpage
```

---

## Lab Status

```text
RB-LINUX-002
├── Package management ........... COMPLETE
├── Basic systemd management ..... COMPLETE
├── Boot enablement .............. COMPLETE
├── Socket verification .......... COMPLETE
├── Local HTTP testing ........... COMPLETE
├── Remote HTTP testing .......... COMPLETE
├── Troubleshooting .............. COMPLETE
└── SR-2001 ...................... CLOSED
```

**Linux Administration Lab #002 — COMPLETE**
