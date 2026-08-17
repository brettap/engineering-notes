# RB-LINUX-004 — Linux Firmware Security Updates with `fwupdmgr`

**Environment:** Techworks Lab  
**Platforms:** Ubuntu Linux / Proxmox-hosted workloads  
**Tool:** `fwupdmgr` / fwupd  
**Change Type:** Security Maintenance  
**Status:** COMPLETE / VERIFIED

---

## 1. Purpose

This runbook documents the procedure for investigating and applying firmware/security updates reported by Ubuntu through `fwupd`.

The procedure was developed after Ubuntu displayed the following login notification:

```text
1 device has a firmware upgrade available.
Run `fwupdmgr get-upgrades` for more information.
```

The objective is to avoid blindly applying firmware changes and instead follow a controlled maintenance workflow:

```text
Notification
     ↓
Investigate
     ↓
Identify affected component
     ↓
Assess risk
     ↓
Establish recovery path
     ↓
Create recovery point
     ↓
Apply update
     ↓
Reboot if required
     ↓
Verify system
     ↓
Verify services
```

---

# 2. Initial Ubuntu Notification

Ubuntu displayed several messages during login.

These represented separate issues:

```text
Ubuntu Login/MOTD
       │
       ├── MicroK8s information
       │      └── Informational
       │
       ├── ESM Apps notification
       │      └── Extended security coverage
       │
       └── Firmware upgrade available
              └── ACTIONABLE
```

Do not assume that every MOTD message represents a system fault.

---

# 3. Investigate Available Firmware Updates

Run:

```bash
fwupdmgr get-upgrades
```

Do **not** immediately run the update command.

First determine:

- affected device/component;
- current firmware/version;
- available version;
- vendor;
- update urgency;
- whether the payload is signed;
- whether a reboot is required.

---

# 4. Update Identified During Lab

The system reported:

```text
QEMU Standard PC (Q35 + ICH9, 2009)
│
└── UEFI dbx
```

Version information:

```text
Current version: 20250902
New version:     20260402
Urgency:         High
```

The update was:

```text
Secure Boot dbx Configuration Update
```

This was **not physical motherboard firmware for the Proxmox server**.

The Ubuntu guest was reporting an update associated with its virtual UEFI/Secure Boot environment.

---

# 5. Understanding UEFI dbx

`dbx` is the UEFI Secure Boot **Forbidden Signature Database**.

Conceptually:

```text
                    Secure Boot
                         │
              ┌──────────┴──────────┐
              │                     │
         Trusted items        Revoked items
              │                     │
         permitted                 dbx
                                    │
                                    ▼
                           forbidden signatures
```

The dbx contains signatures/certificates associated with boot components that should no longer be trusted.

The update reported:

```text
Summary:
UEFI Secure Boot Forbidden Signature Database

Purpose:
Update the list of forbidden signatures
to the latest release.
```

The release addressed insecure bootloaders capable of bypassing Secure Boot.

---

# 6. Why the Update Was Considered Legitimate

The update metadata included:

```text
Urgency: High
Signed Payload
Trusted metadata
Ubuntu 24.04 tested
Reboot required
```

Therefore, the update was treated as a legitimate security maintenance item rather than ignored.

---

# 7. Maintenance Decision Process

Before applying firmware/security updates:

```text
Update discovered
       │
       ▼
Identify component
       │
       ▼
Security relevant?
       │
       ▼
Understand impact
       │
       ▼
Reboot required?
       │
       ▼
Verify recovery path
       │
       ▼
Create recovery point
       │
       ▼
Apply update
```

Do not use:

```text
"Firmware available"
       ↓
Immediately install
```

without first determining what is being changed.

---

# 8. Recovery Preparation

Because this update affected UEFI/Secure Boot state and required a reboot, a recovery point was created before installation.

For DevOps02:

```text
Proxmox
   │
   ▼
pve02
   │
   ▼
VM 300 — devops-02
   │
   ▼
Snapshot
```

Example snapshot name:

```text
pre-uefi-dbx-update-20260816
```

Example description:

```text
Before UEFI Secure Boot dbx update 20250902 -> 20260402
```

RAM state was not required for this maintenance snapshot.

---

# 9. Redundant Administrative Access

Before boot-affecting maintenance, verify recovery access.

For DevOps02:

```text
                   Administrator
                         │
            ┌────────────┴────────────┐
            │                         │
           SSH                  Proxmox Console
            │                         │
     Normal management          Break-glass path
            │                         │
            └────────────┬────────────┘
                         │
                         ▼
                      DevOps02
```

This provides an alternative management path if SSH does not return following the reboot.

---

# 10. Pre-Update Check

Immediately before applying the change:

```bash
fwupdmgr get-upgrades
```

Verify that the expected update is still the one being offered.

Do not continue if an unexpected firmware target or materially different update appears without investigating it first.

---

# 11. Apply Firmware Update

Run:

```bash
sudo fwupdmgr update
```

Review all prompts before accepting them.

Do not force an update through unexpected Secure Boot, signature, compatibility, or device warnings.

---

# 12. Reboot

If `fwupdmgr` reports that a reboot is required:

```bash
sudo reboot
```

Expected workflow:

```text
fwupdmgr update
       │
       ▼
Update staged
       │
       ▼
Reboot
       │
       ▼
Virtual UEFI
       │
       ▼
dbx update
       │
       ▼
Ubuntu boot
       │
       ▼
System services
```

---

# 13. Post-Update Firmware Verification

After the system returns:

```bash
fwupdmgr get-upgrades
```

Verify that the previously offered update is no longer outstanding or that the reported version reflects the expected state.

For the lab update:

```text
Old:
20250902

Expected updated state:
20260402
```

---

# 14. Verify Critical Services

A successful reboot does not by itself complete the maintenance change.

Check required services.

Example:

```bash
systemctl is-active ssh
systemctl is-active nginx
```

Expected:

```text
active
active
```

Where applicable, also verify automatic startup configuration:

```bash
systemctl is-enabled ssh
systemctl is-enabled nginx
```

---

# 15. Remote Connectivity Verification

From the management workstation:

```powershell
Test-NetConnection 192.168.1.137 -Port 22
```

For the nginx service:

```powershell
Test-NetConnection 192.168.1.137 -Port 80
```

Expected:

```text
TcpTestSucceeded : True
```

Application-layer testing should also be performed where applicable.

Example:

```text
http://192.168.1.137
```

or locally:

```bash
curl -I http://localhost
```

---

# 16. Verification Layers

Do not rely on a single test.

```text
             POST-MAINTENANCE VERIFICATION

                    VM running?
                         │
                         ▼
                    OS booted?
                         │
                         ▼
                 SSH service active?
                         │
                         ▼
                  TCP/22 reachable?
                         │
                         ▼
               Application active?
                         │
                         ▼
              Application port open?
                         │
                         ▼
              Application responds?
                         │
                         ▼
                      HEALTHY
```

---

# 17. Maintenance Procedure

Use the following sequence for future `fwupd` maintenance:

```text
1. Receive firmware notification
              │
              ▼
2. fwupdmgr get-upgrades
              │
              ▼
3. Identify exact component
              │
              ▼
4. Review version / urgency / reboot requirement
              │
              ▼
5. Verify administrative recovery access
              │
              ▼
6. Create snapshot/backup where appropriate
              │
              ▼
7. sudo fwupdmgr update
              │
              ▼
8. Review update result
              │
              ▼
9. Reboot if required
              │
              ▼
10. Verify firmware state
              │
              ▼
11. Verify SSH
              │
              ▼
12. Verify application services
              │
              ▼
13. Verify remote connectivity
              │
              ▼
14. Close maintenance
```

---

# 18. Maintenance Checklist

- [ ] Run `fwupdmgr get-upgrades`.
- [ ] Identify the affected component.
- [ ] Record current version.
- [ ] Record proposed version.
- [ ] Review update urgency.
- [ ] Determine whether reboot is required.
- [ ] Verify SSH/normal administrative access.
- [ ] Verify console/break-glass access where available.
- [ ] Verify current backups.
- [ ] Create snapshot/recovery point when appropriate.
- [ ] Run `sudo fwupdmgr update`.
- [ ] Review all warnings/prompts.
- [ ] Reboot if required.
- [ ] Verify the system returns.
- [ ] Run `fwupdmgr get-upgrades` again.
- [ ] Verify SSH.
- [ ] Verify required application services.
- [ ] Verify required network ports.
- [ ] Verify applications from a client.
- [ ] Record maintenance result.

---

# 19. Useful Commands

```bash
# Discover firmware updates
fwupdmgr get-upgrades

# Apply available updates
sudo fwupdmgr update

# Reboot
sudo reboot

# Verify SSH
systemctl status ssh
systemctl is-active ssh
systemctl is-enabled ssh

# Inspect listening ports
sudo ss -tulnp

# Verify nginx
systemctl status nginx
systemctl is-active nginx

# Test local HTTP
curl -I http://localhost
```

Windows remote verification:

```powershell
Test-NetConnection <server-IP> -Port 22
Test-NetConnection <server-IP> -Port 80
```

---

# 20. Important Distinction — Guest vs Physical Firmware

In a virtualized environment:

```text
                Physical Proxmox Host
                         │
                         │ QEMU/KVM
                         ▼
                 Virtual Machine
                         │
                  Virtual hardware
                         │
                    UEFI/OVMF
                         │
                         ▼
                     Ubuntu
                         │
                         ▼
                      fwupd
```

A firmware notification inside an Ubuntu VM does **not automatically mean the physical Proxmox host requires a firmware update**.

Always inspect the device reported by:

```bash
fwupdmgr get-upgrades
```

before deciding what needs maintenance.

---

# 21. Completed DevOps02 Change

```text
DevOps02
192.168.1.137
VM 300
   │
   ├── Firmware notification investigated
   │
   ├── UEFI dbx update identified
   │
   ├── Security relevance established
   │
   ├── Proxmox recovery access verified
   │
   ├── Snapshot created
   │
   ├── fwupdmgr update completed
   │
   ├── Reboot completed
   │
   └── Services/connectivity verified
```

---

# 22. Additional Host Maintenance

The maintenance task was subsequently completed on the additional applicable system associated with **pve01**.

Operational observations:

```text
pve01-related maintenance
│
├── Firmware maintenance completed
├── SSH remained active
└── Firewall configuration unchanged
```

No firewall change was required as part of the firmware maintenance.

This is important because unrelated configuration should generally **not be modified merely because a maintenance window exists**.

```text
Firmware maintenance
        │
        ├── Update firmware/security component
        ├── Reboot if required
        ├── Verify services
        └── Verify connectivity

        NOT

Firmware maintenance
        │
        └── Opportunistically change unrelated firewall policy
```

Firewall hardening should be handled as its own planned and verified configuration change.

---

# 23. Lessons Learned

1. Ubuntu's firmware notification should be investigated rather than blindly accepted or ignored.

2. `fwupdmgr get-upgrades` identifies the actual device and update.

3. A VM can report virtual UEFI/Secure Boot updates; this does not necessarily represent physical host firmware.

4. UEFI `dbx` contains revoked/forbidden Secure Boot signatures.

5. Security firmware updates can affect the boot chain and deserve controlled maintenance procedures.

6. Establish recovery access before making boot-affecting changes.

7. Hypervisor console access provides an important break-glass path for VMs.

8. A snapshot can provide an additional recovery point before significant VM changes.

9. Maintenance is not complete when the update command succeeds; the system and its services must be verified afterward.

10. SSH availability should be explicitly tested following reboot.

11. Application availability should be tested separately from OS availability.

12. Avoid combining unrelated configuration changes with a maintenance task without a specific reason.

---

# 24. Final Maintenance Model

```text
                SECURITY MAINTENANCE

                   Notification
                        │
                        ▼
                    Investigate
                        │
                        ▼
                 Assess relevance
                        │
                        ▼
                Establish recovery
                  /             \
               SSH             Console
                  \             /
                        │
                        ▼
                 Snapshot/backup
                        │
                        ▼
                  Apply update
                        │
                        ▼
                     Reboot
                        │
                        ▼
                Verify firmware
                        │
                        ▼
                  Verify OS
                        │
                        ▼
                 Verify services
                        │
                        ▼
                Verify network
                        │
                        ▼
                Verify application
                        │
                        ▼
                     CLOSE
```

**RB-LINUX-004 Status: COMPLETE**
