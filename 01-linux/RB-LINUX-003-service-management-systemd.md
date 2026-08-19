# RB-LINUX-003 — UFW Firewall Configuration, SSH Lockout Recovery, and Redundant Administrative Access

**Systems:** Ubuntu Linux VMs on Proxmox  
**Incident System:** DevOps02 — `192.168.1.137`  
**Topics:** UFW, SSH, systemd, Remote Administration, Break-Glass Access  
**Status:** COMPLETE / VERIFIED

---

## 1. Purpose

Establish a safe procedure for enabling and modifying UFW on remotely administered Linux systems without accidentally eliminating administrative access.

This runbook was developed following an actual lab incident in which enabling UFW prevented SSH access to DevOps02.

---

# 2. Administrative Access Design

Every remotely administered system should have a primary management path and, where infrastructure permits, an independent recovery path.

```text
                       ADMINISTRATOR
                            │
               ┌────────────┴────────────┐
               │                         │
               ▼                         ▼
        PRIMARY ACCESS              BREAK-GLASS
             SSH                    VM CONSOLE
               │                         │
          Network path              Proxmox access
               │                         │
          UFW TCP/22                     │
               │                         │
               └────────────┬────────────┘
                            ▼
                         DevOps02
```

For the current environment:

```text
Primary:
Windows workstation
        ↓
TCP/22
        ↓
SSH
        ↓
DevOps02

Break-glass:
Proxmox Web UI
        ↓
VM Console
        ↓
DevOps02
```

The Proxmox console does not depend on the guest's SSH service or UFW permitting TCP/22.

---

# 3. Standing Remote Administration Rule

> **Do not modify firewall, routing, network-interface, SSH, or authentication configuration on a remotely administered system until a recovery access method has been verified.**

Before security/network changes:

```text
Verify console access
        ↓
Verify SSH running
        ↓
Verify SSH enabled at boot
        ↓
Verify listening socket
        ↓
Identify management network
        ↓
Create management firewall rule
        ↓
Create application rules
        ↓
Enable/change firewall
        ↓
Test SECOND SSH connection
        ↓
Keep existing session/console open
        ↓
Close only after verification
```

---

# 4. Incident — SSH Access Lost After Enabling UFW

## Symptom

Remote connection to DevOps02 failed:

```text
Windows
   │
   │ TCP/22
   ▼
192.168.1.137
   │
   X
TIMEOUT
```

DevOps02 remained operational and was accessible through the Proxmox VM console.

---

# 5. Initial Investigation

SSH was inspected through the Proxmox console.

```bash
systemctl status ssh
```

The SSH service was:

```text
active (running)
```

but initially not enabled for automatic startup.

It was subsequently enabled.

```bash
sudo systemctl enable ssh
```

Verification:

```bash
systemctl is-enabled ssh
systemctl status ssh
```

This established two independent properties:

```text
ACTIVE
  │
  └── SSH is running NOW

ENABLED
  │
  └── SSH should start at BOOT
```

Enabling SSH did not restore network connectivity because the daemon itself was not the cause of the connection failure.

---

# 6. Verify Listening Socket

Use:

```bash
sudo ss -tlnp | grep ':22'
```

This determines whether a process is actually listening for TCP connections on port 22.

Troubleshooting layers:

```text
ssh.service active?
       ↓
TCP/22 listening?
       ↓
Firewall permitting TCP/22?
       ↓
Network path available?
       ↓
Client connection succeeds?
```

---

# 7. Inspect UFW

Check detailed status:

```bash
sudo ufw status verbose
```

Check numbered rules:

```bash
sudo ufw status numbered
```

Actual firewall state discovered:

```text
Status: active

Default:
deny incoming
allow outgoing
deny routed

Explicit inbound rules:
TCP/80 nginx → ALLOW
TCP/22 SSH   → NO RULE
```

---

# 8. Root Cause

UFW had been enabled with a default inbound deny policy.

nginx had an explicit HTTP exception, but SSH did not.

```text
                       UFW
                        │
              Default inbound DENY
                        │
              ┌─────────┴─────────┐
              │                   │
           TCP/80              TCP/22
              │                   │
        Explicit ALLOW          No rule
              │                   │
              ▼                   ▼
            nginx                DROP
              ✓                   X
                                 SSH
```

Therefore:

```text
sshd running ................ YES
TCP/22 listening ............ YES
UFW active .................. YES
UFW permits TCP/22 .......... NO
Remote SSH .................. TIMEOUT
```

The service was healthy.

The firewall prevented the connection from reaching it.

---

# 9. Remediation

Rather than disabling UFW or exposing SSH universally, SSH was permitted from the trusted LAN:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
```

This creates the intended security model:

```text
                 DevOps02
               192.168.1.137
                     │
                    UFW
                     │
          Default inbound DENY
               ┌─────┴─────┐
               │           │
       192.168.1.0/24     Other
               │           │
          TCP/22 SSH       │
               │           │
             ALLOW        DENY
               │
               ▼
              sshd
```

---

# 10. Verify Firewall Rules

```bash
sudo ufw status numbered
```

Expected design includes:

```text
TCP/80     ALLOW     required HTTP access
TCP/22     ALLOW     192.168.1.0/24
```

Exact application exposure should always reflect the actual service requirements.

---

# 11. Verify from Windows

Before terminating console access, test TCP/22 from the management workstation:

```powershell
Test-NetConnection 192.168.1.137 -Port 22
```

Expected:

```text
TcpTestSucceeded : True
```

Then establish a new SSH session.

Do not consider the firewall change complete until a **new connection** succeeds.

---

# 12. Why a New SSH Session Matters

An existing SSH session may remain operational even after firewall changes that prevent new connections.

Therefore:

```text
Existing SSH session works
          ≠
New SSH connections work
```

Safe procedure:

```text
SSH Session #1
KEEP OPEN
     │
     ├── Make firewall change
     │
     ▼
SSH Session #2
NEW CONNECTION
     │
     ├── succeeds → configuration validated
     │
     └── fails ───→ use Session #1 / console to recover
```

---

# 13. Firewall Change Procedure

Before enabling UFW on a remote Linux server:

```bash
systemctl status ssh
systemctl is-enabled ssh
sudo ss -tlnp | grep ':22'
```

Confirm break-glass console access.

Then establish required firewall rules **before** enabling the firewall.

Example trusted-LAN SSH rule:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
```

Add required application rules.

Example:

```bash
sudo ufw allow 'Nginx HTTP'
```

Inspect:

```bash
sudo ufw status verbose
```

Then enable UFW:

```bash
sudo ufw enable
```

Immediately test a new management connection.

---

# 14. Break-Glass Recovery Procedure

If SSH is lost:

```text
SSH unavailable
      │
      ▼
DO NOT PANIC/REBOOT
      │
      ▼
Use Proxmox console
      │
      ▼
Check IP configuration
      │
      ▼
Check ssh.service
      │
      ▼
Check TCP/22 listener
      │
      ▼
Check UFW
      │
      ▼
Correct rule
      │
      ▼
Test TCP/22 remotely
      │
      ▼
Open NEW SSH session
      │
      ▼
RECOVERED
```

Useful commands:

```bash
ip addr
systemctl status ssh
systemctl is-enabled ssh
sudo ss -tlnp | grep ':22'
sudo ufw status verbose
sudo ufw status numbered
```

---

# 15. Do Not Immediately Disable the Firewall

This command:

```bash
sudo ufw disable
```

may restore connectivity, but it also removes the protection the firewall was intended to provide and can obscure the actual configuration problem.

Prefer:

```text
Identify blocked requirement
        ↓
Determine legitimate source
        ↓
Create narrow allow rule
        ↓
Verify
```

Use firewall disablement as a deliberate troubleshooting/recovery decision, not as the default response to a connectivity problem.

---

# 16. Core Security Principle

Use:

> **Default deny + explicit allow**

instead of:

> **Allow everything unless specifically blocked**

Conceptually:

```text
Incoming packet
      │
      ▼
Explicit legitimate rule?
     / \
   YES  NO
    │    │
 ALLOW  DENY
```

---

# 17. Service State vs Network Accessibility

A major lesson from this incident:

```text
APPLICATION LAYER

ssh.service
    │
    ├── active
    └── enabled
         │
         ▼
NETWORK SOCKET
    TCP/22 listening
         │
         ▼
HOST FIREWALL
       UFW
         │
    ALLOW / DENY
         │
         ▼
NETWORK PATH
         │
         ▼
CLIENT
```

Each layer must be verified independently.

`systemctl status ssh` reporting `active (running)` does **not** prove that a remote client can reach SSH.

---

# 18. Operational Checklist

- [ ] Verify break-glass console access.
- [ ] Verify server IP address.
- [ ] Verify SSH is active.
- [ ] Verify SSH is enabled at boot.
- [ ] Verify TCP/22 is listening.
- [ ] Identify trusted management network.
- [ ] Add SSH firewall rule.
- [ ] Add required application firewall rules.
- [ ] Review firewall configuration.
- [ ] Enable/change firewall.
- [ ] Keep current administrative session open.
- [ ] Test TCP/22 from management workstation.
- [ ] Establish a second/new SSH connection.
- [ ] Verify application connectivity.
- [ ] Review firewall rules after testing.
- [ ] Document change and validation.

---

# 19. Incident Resolution

```text
INCIDENT
SSH timeout to DevOps02
        │
        ▼
Console access retained
        │
        ▼
sshd confirmed healthy
        │
        ▼
UFW inspected
        │
        ▼
Default inbound DENY discovered
        │
        ▼
No TCP/22 allow rule
        │
        ▼
Trusted LAN SSH rule created
        │
        ▼
Remote TCP/22 verified
        │
        ▼
SSH restored
```

**Root Cause:** UFW was enabled with default inbound deny without first permitting SSH from the management network.

**Resolution:** Explicitly allowed TCP/22 from `192.168.1.0/24`.

**Preventive Control:** Verify redundant administrative access and required management firewall rules before changing remote network/security configuration.

**Status:** RESOLVED / VERIFIED



---------------------------------------------------------------------

Now, the Ubuntu messages.

The first thing I'd do is separate **three unrelated messages** that Ubuntu has put together in the login banner:

```text
MicroK8s advertisement
        │
        └── informational — ignore

ESM Apps message
        │
        └── Ubuntu Pro/extended security coverage
            not an immediate failure

Firmware upgrade available
        │
        └── INVESTIGATE
```

The MicroK8s message is essentially Ubuntu's MOTD informational/promotional content. It doesn't mean Kubernetes or MicroK8s is installed or that you need it.

The **ESM Apps** message means an update for a package covered by Ubuntu's Expanded Security Maintenance application repository is available, while that service isn't enabled. That's worth understanding later, but `0 updates can be applied immediately` means your normal configured repositories currently have nothing pending.

The firmware notification is the one I want to investigate now.

On **each Ubuntu server**, run:

```bash
fwupdmgr get-upgrades
```

Don't install anything yet.

We're specifically looking for:

```text
Device
   │
   ├── what hardware?
   ├── current firmware version?
   ├── available version?
   └── what type of firmware?
```

