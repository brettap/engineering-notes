# RB-LINUX-008 — Package Management, Patching, and Repositories

## Document Control

| Field           | Value                                          |
| --------------- | ---------------------------------------------- |
| Runbook ID      | RB-LINUX-008                                   |
| Title           | Package Management, Patching, and Repositories |
| Platform        | Ubuntu Linux                                   |
| Test System     | `devops02`                                     |
| OS              | Ubuntu 24.04.4 LTS                             |
| Package Manager | APT / DPKG                                     |
| Workload        | Nginx                                          |
| Status          | Complete                                       |
| Date Completed  | 2026-08-20                                     |

---

# 1. Purpose

This runbook documents the operational process for safely assessing, patching, and validating packages on an Ubuntu Linux system.

The objective is not simply to install available updates, but to perform package maintenance using a controlled system-administration workflow that includes:

* Establishing a system baseline
* Reviewing configured repositories
* Refreshing package metadata
* Identifying pending updates
* Determining whether updates affect a production service
* Validating the service before patching
* Creating a configuration backup
* Limiting the scope of the package change
* Verifying package installation
* Validating service health after patching
* Determining whether a reboot is required

---

# 2. Scenario

A scheduled Linux patch cycle was performed on `devops02`.

APT reported two available updates:

```text
nginx-common
nginx
```

Both updates were available from the Ubuntu `noble-security` repository.

The task was therefore treated as a controlled security-related application patch rather than as an unrestricted operating system upgrade.

---

# 3. Change Workflow

```text
CHANGE REQUEST
      │
      ▼
Establish System Baseline
      │
      ├── OS version
      ├── Running kernel
      └── Existing reboot state
      │
      ▼
Review Configured Repositories
      │
      ▼
Refresh Package Metadata
      │
      ▼
Identify Available Updates
      │
      ▼
Identify Affected Workload
      │
      └── Nginx
      │
      ▼
Pre-Change Validation
      │
      ├── Service running?
      ├── Configuration valid?
      └── Configuration backed up?
      │
      ▼
Control Change Scope
      │
      ▼
Patch Selected Packages
      │
      ▼
Post-Change Validation
      │
      ├── Correct versions installed?
      ├── Configuration valid?
      ├── Service running?
      ├── Updates remaining?
      └── Reboot required?
      │
      ▼
CHANGE COMPLETE
```

---

# 4. Phase 1 — Establish System Baseline

## 4.1 Identify Operating System

Command:

```bash
cat /etc/os-release
```

Observed:

```text
PRETTY_NAME="Ubuntu 24.04.4 LTS"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
VERSION_CODENAME=noble
```

Result:

```text
Ubuntu 24.04.4 LTS
Codename: noble
```

---

## 4.2 Identify Running Kernel

Command:

```bash
uname -r
```

Observed:

```text
6.8.0-138-generic
```

This establishes the running kernel before package maintenance begins.

---

# 5. Phase 2 — Review APT Repositories

Command:

```bash
add-apt-repository --list
```

Configured Ubuntu repositories included:

```text
http://us.archive.ubuntu.com/ubuntu/
```

Suites:

```text
noble
noble-updates
noble-backports
```

Security repository:

```text
http://security.ubuntu.com/ubuntu/
```

Suite:

```text
noble-security
```

Components:

```text
main
restricted
universe
multiverse
```

Repository flow:

```text
Ubuntu Repositories
       │
       ├── noble
       │     └── Base release packages
       │
       ├── noble-updates
       │     └── General supported updates
       │
       ├── noble-backports
       │     └── Newer packages backported to Noble
       │
       └── noble-security
             └── Security-related package updates
```

---

# 6. Phase 3 — Refresh Package Metadata

Command:

```bash
sudo apt update
```

Observed:

```text
Hit:1 http://security.ubuntu.com/ubuntu noble-security InRelease
Hit:2 http://us.archive.ubuntu.com/ubuntu noble InRelease
Hit:3 http://us.archive.ubuntu.com/ubuntu noble-updates InRelease
Hit:4 http://us.archive.ubuntu.com/ubuntu noble-backports InRelease
```

APT reported:

```text
2 packages can be upgraded.
```

## Important Concept

The following command:

```bash
sudo apt update
```

does **not** install package updates.

It refreshes the local APT package index using information from configured repositories.

```text
APT Repository
      │
      ▼
sudo apt update
      │
      ▼
Local package metadata refreshed
      │
      ▼
System now knows which newer packages are available
```

---

# 7. Phase 4 — Identify Available Packages

Command:

```bash
apt list --upgradable
```

Observed:

```text
nginx-common/noble-updates,noble-security 1.24.0-2ubuntu7.17 all
[upgradable from: 1.24.0-2ubuntu7.16]

nginx/noble-updates,noble-security 1.24.0-2ubuntu7.17 amd64
[upgradable from: 1.24.0-2ubuntu7.16]
```

Two packages required updates:

| Package      | Current            | Available          |
| ------------ | ------------------ | ------------------ |
| nginx        | 1.24.0-2ubuntu7.16 | 1.24.0-2ubuntu7.17 |
| nginx-common | 1.24.0-2ubuntu7.16 | 1.24.0-2ubuntu7.17 |

Because the packages were available through:

```text
noble-security
```

the change had security relevance.

---

# 8. Check Existing Reboot Requirement

Command:

```bash
[ -f /var/run/reboot-required ] && echo "Reboot required" || echo "No reboot needed"
```

Observed:

```text
No reboot needed
```

This established that no reboot was already pending before the maintenance operation.

---

# 9. Phase 5 — Pre-Change Application Validation

Because the package update affected Nginx, the service was validated before the patch.

The operational principle is:

```text
Is the service healthy?
        │
        ▼
Is the configuration valid?
        │
        ▼
Can the configuration be recovered?
        │
        ▼
Perform package change
```

---

## 9.1 Verify Nginx Service Status

Command:

```bash
systemctl status nginx --no-pager
```

Observed:

```text
Active: active (running)
```

Main process:

```text
nginx: master process
```

Worker processes were also running.

Result:

```text
Pre-change Nginx service health: PASS
```

---

## 9.2 Validate Nginx Configuration

Command:

```bash
sudo nginx -t
```

Observed:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Result:

```text
Pre-change configuration validation: PASS
```

This command validates the configuration without requiring a service restart or reload.

---

## 9.3 Back Up Nginx Configuration

Recommended command:

```bash
sudo cp -a /etc/nginx "/etc/nginx.backup-$(date +%Y%m%d-%H%M)"
```

The `-a` option uses archive mode and preserves attributes such as:

* Permissions
* Ownership
* Timestamps
* Symbolic links
* Directory structure

The timestamp allows multiple backups to be retained without overwriting previous copies.

Verification:

```bash
ls -ld /etc/nginx*
```

---

# 10. Phase 6 — Apply Controlled Package Upgrade

Rather than upgrading all packages on the server, the maintenance operation was restricted specifically to the affected Nginx packages.

Command:

```bash
sudo apt install --only-upgrade nginx nginx-common
```

APT reported:

```text
The following packages will be upgraded:
  nginx nginx-common

2 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```

Package transition:

```text
nginx
1.24.0-2ubuntu7.16
        │
        ▼
1.24.0-2ubuntu7.17

nginx-common
1.24.0-2ubuntu7.16
        │
        ▼
1.24.0-2ubuntu7.17
```

Installation completed successfully.

---

# 11. Why `--only-upgrade` Was Used

Instead of:

```bash
sudo apt upgrade
```

the following was used:

```bash
sudo apt install --only-upgrade nginx nginx-common
```

This limits the scope of the change.

Advantages include:

* Only approved packages are modified.
* Additional unrelated packages are not changed.
* Change impact is easier to understand.
* Rollback and troubleshooting scope is smaller.
* The operation better aligns with change-management principles.

---

# 12. Package Maintenance Side Effects

During the Nginx upgrade, APT displayed:

```text
Processing triggers for ufw...
Rules updated for profile 'Nginx HTTP'
Skipped reloading firewall
```

This demonstrates an important package-management principle:

> Updating one package can invoke scripts or triggers belonging to other system components.

Although the requested change involved Nginx, the package operation also interacted with UFW.

Therefore:

```text
apt completed successfully
```

does not by itself prove that the maintenance operation is complete.

Post-change system validation is still required.

---

# 13. Service Restart Observation

Before patching, Nginx had been running since:

```text
Wed 2026-08-19 21:01:14 UTC
```

After patching, Nginx reported:

```text
Active: active (running) since Thu 2026-08-20 21:02:15 UTC
```

This indicates that the package upgrade restarted or replaced the running Nginx service during the maintenance process.

This reinforces why service health must be validated **after** package maintenance.

---

# 14. Phase 7 — Post-Change Validation

## 14.1 Validate Nginx Configuration

Command:

```bash
sudo nginx -t
```

Observed:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Result:

```text
Post-change configuration validation: PASS
```

---

# 15. Verify Installed Package Versions

Command:

```bash
dpkg -l nginx nginx-common
```

Observed:

```text
ii  nginx          1.24.0-2ubuntu7.17 amd64
ii  nginx-common   1.24.0-2ubuntu7.17 all
```

The `ii` package status indicates:

```text
Desired state: Installed
Current state: Installed
```

Result:

```text
nginx        1.24.0-2ubuntu7.17
nginx-common 1.24.0-2ubuntu7.17
```

Package verification: **PASS**

---

# 16. Verify Service Health

Command:

```bash
systemctl status nginx --no-pager
```

Observed:

```text
Active: active (running)
```

Main PID:

```text
26929
```

Result:

```text
Post-change service validation: PASS
```

---

# 17. Verify Remaining Updates

Command:

```bash
apt list --upgradable
```

Observed:

```text
Listing... Done
```

No packages were listed.

Result:

```text
Remaining package updates: NONE
```

---

# 18. Verify Reboot Requirement

Command:

```bash
[ -f /var/run/reboot-required ] && echo "Reboot required" || echo "No reboot needed"
```

Observed:

```text
No reboot needed
```

Result:

```text
Post-change reboot requirement: NONE
```

A more diagnostic version is:

```bash
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs || echo "No reboot required"
```

If a reboot is required, `/var/run/reboot-required.pkgs` can identify packages associated with that reboot requirement.

---

# 19. Additional APT Post-Patch Output

The package operation also reported:

```text
Running kernel seems to be up-to-date.

No services need to be restarted.

No containers need to be restarted.

No user sessions are running outdated binaries.

No VM guests are running outdated hypervisor (qemu) binaries on this host.
```

This provided additional evidence that no broader operating-system restart action was required.

---

# 20. Final System State

```text
devops02
│
├── OS
│   └── Ubuntu 24.04.4 LTS
│
├── Kernel
│   └── 6.8.0-138-generic
│
├── Repositories
│   ├── noble
│   ├── noble-updates
│   ├── noble-backports
│   └── noble-security
│
├── Nginx
│   ├── Version: 1.24.0-2ubuntu7.17
│   ├── Status: active (running)
│   └── Configuration: valid
│
├── nginx-common
│   └── Version: 1.24.0-2ubuntu7.17
│
├── Pending upgrades
│   └── None
│
└── Reboot required
    └── No
```

---

# 21. Troubleshooting / Lessons Learned

## 21.1 Incorrect `apt list` Option

An initial command contained a typo:

```bash
apt list --upgrageable
```

APT returned:

```text
E: Command line option --upgrageable is not understood
```

Correct command:

```bash
apt list --upgradable
```

`apt list --upgradeable` may also be accepted by the installed APT version, but `--upgradable` is the standard form to retain in the runbook.

---

## 21.2 Do Not Reload a Service Without a Reason

An initial consideration was:

```bash
sudo systemctl reload nginx
```

before patching.

This was unnecessary because no configuration changes had yet been made.

A reload tells Nginx to reread its configuration.

For pre-patch validation, the better command is:

```bash
sudo nginx -t
```

This validates the configuration without applying or reloading it.

---

## 21.3 Baseline Health Before Making Changes

A service should be validated before maintenance.

Otherwise, a pre-existing problem could incorrectly be blamed on the package update.

Operational pattern:

```text
BEFORE CHANGE
     │
     ├── Service healthy?
     ├── Configuration valid?
     └── Recovery path available?
             │
             ▼
          CHANGE
             │
             ▼
AFTER CHANGE
     │
     ├── Package state correct?
     ├── Service healthy?
     ├── Configuration valid?
     └── Reboot required?
```

---

# 22. Operational Takeaways

The primary lesson from this runbook is that Linux patching is more than executing:

```bash
sudo apt update
sudo apt upgrade
```

A production-oriented patch cycle requires understanding the application affected by the package change.

The workflow should be:

```text
Inventory
   ↓
Assess
   ↓
Validate
   ↓
Protect
   ↓
Patch
   ↓
Verify
   ↓
Document
```

Package operations may also trigger changes to related components, making post-change validation mandatory.

Controlled package targeting using:

```bash
sudo apt install --only-upgrade <package>
```

can reduce change scope when only specific packages are approved for maintenance.

---

# 23. Command Reference

## System Identification

### Display Ubuntu release information

```bash
cat /etc/os-release
```

Displays Linux distribution information including version, codename, and release metadata.

---

### Display running kernel

```bash
uname -r
```

Displays the currently running Linux kernel version.

---

# Repository Management

### List configured APT repositories

```bash
add-apt-repository --list
```

Displays configured Ubuntu software repositories.

---

### Refresh APT package metadata

```bash
sudo apt update
```

Downloads updated package metadata from configured repositories.

This command does **not** install package upgrades.

---

# Package Assessment

### Display packages eligible for upgrade

```bash
apt list --upgradable
```

Lists installed packages for which newer versions are available.

---

### Upgrade selected installed packages only

```bash
sudo apt install --only-upgrade nginx nginx-common
```

Upgrades the specified packages without intentionally expanding the maintenance operation to unrelated installed packages.

---

### Display package installation status and version

```bash
dpkg -l nginx nginx-common
```

Displays package state, installed version, architecture, and description.

---

# Service Management

### Display Nginx service status

```bash
systemctl status nginx --no-pager
```

Shows whether Nginx is running and provides recent systemd status information without opening a pager.

---

### Validate Nginx configuration

```bash
sudo nginx -t
```

Checks Nginx configuration syntax and validity without requiring a reload or restart.

---

### Reload Nginx

```bash
sudo systemctl reload nginx
```

Causes Nginx to reread its configuration while attempting to avoid a full service restart.

Use when configuration changes have actually been made and validated.

---

# Configuration Backup

### Create timestamped Nginx configuration backup

```bash
sudo cp -a /etc/nginx "/etc/nginx.backup-$(date +%Y%m%d-%H%M)"
```

Creates an archive-mode copy of the Nginx configuration while preserving file metadata.

---

### Verify Nginx configuration directories and backups

```bash
ls -ld /etc/nginx*
```

Lists Nginx configuration directories and backup copies.

---

# Reboot Assessment

### Check whether Ubuntu requires a reboot

```bash
[ -f /var/run/reboot-required ] && echo "Reboot required" || echo "No reboot needed"
```

Tests for Ubuntu's reboot-required marker file.

---

### Identify packages associated with a reboot requirement

```bash
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs || echo "No reboot required"
```

Displays packages associated with a pending reboot when available.

---

# 24. Completion Criteria

RB-LINUX-008 is considered successfully completed when:

* [x] Ubuntu version identified
* [x] Running kernel identified
* [x] Package repositories reviewed
* [x] APT metadata refreshed
* [x] Pending updates identified
* [x] Security repository involvement identified
* [x] Affected production service identified
* [x] Service health validated before patching
* [x] Application configuration validated
* [x] Configuration backup created
* [x] Package change scope controlled
* [x] Nginx packages upgraded
* [x] Installed package versions verified
* [x] Application configuration validated after patching
* [x] Service health verified after patching
* [x] Remaining package updates checked
* [x] Reboot requirement checked
* [x] Operational findings documented

---

# 25. Final Result

**RB-LINUX-008 — Package Management / Patching / Repositories: COMPLETE**

The Ubuntu server was successfully assessed and patched using a controlled package-maintenance workflow.

Nginx and `nginx-common` were upgraded from:

```text
1.24.0-2ubuntu7.16
```

to:

```text
1.24.0-2ubuntu7.17
```

Post-maintenance validation confirmed:

```text
Nginx service:       ACTIVE
Nginx configuration: VALID
Pending upgrades:    NONE
Reboot required:     NO
Change result:       SUCCESS
```
