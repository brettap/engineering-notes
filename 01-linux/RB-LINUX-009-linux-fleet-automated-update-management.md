# RB-009 - Linux Fleet Automated Update Management

## Purpose

Implement and validate a controlled automated patch-management process for Ubuntu/Debian Linux servers.

The solution provides:

* Automated package repository refresh.
* Automated package upgrades.
* Package cache cleanup.
* Explicit exclusion of Proxmox VE hypervisors.
* Host identification.
* Persistent update logging.
* Package-upgrade verification.
* Detection of remaining upgradeable packages.
* Kernel/reboot-required detection.
* Success/failure reporting.
* SMTP email infrastructure.
* Canary testing before fleet deployment.

This runbook establishes the foundation for future Git-based configuration management, CI validation, Ansible deployment, and automated fleet maintenance.

---

# Environment

Initial canary system:

```text
Hostname: locator01
Operating System: Ubuntu 26.04 LTS
Architecture: x86_64
IP Address: 192.168.1.144
```

Update script:

```text
/usr/local/bin/sys-update.sh
```

Update log:

```text
/var/log/server-autoupdate.log
```

SMTP configuration:

```text
/etc/msmtprc
```

---

# Architecture

```text
                         Git Repository
                              |
                       Future source of truth
                              |
                              v
                     sys-update.sh
                              |
                              v
                       Linux Server
                              |
                 +------------+------------+
                 |                         |
             Proxmox?                  Debian?
                 |                         |
                YES                       YES
                 |                         |
               SKIP                        v
                                     apt-get update
                                           |
                                     apt-get upgrade
                                           |
                                      apt-get clean
                                           |
                                           v
                                Check remaining updates
                                           |
                                           v
                                Check reboot required
                                           |
                                           v
                                     Write report
                                           |
                                           v
                                          SMTP
                                           |
                                           v
                                  Administrator
```

---

# Operational Policy

## Ubuntu/Debian Servers

Normal Ubuntu/Debian servers may use the automated update workflow.

## Proxmox VE

Proxmox VE is Debian-based and therefore contains:

```text
/etc/debian_version
```

A generic Debian detection test would therefore incorrectly classify Proxmox hosts as ordinary Debian servers.

The script checks for Proxmox first:

```bash
command -v pveversion
```

If detected, automated generic patching is skipped.

Proxmox hosts will use a separate maintenance policy.

---

# Update Script

Location:

```text
/usr/local/bin/sys-update.sh
```

Current script:

```bash
#!/bin/bash

# Define log file
LOG_FILE="/var/log/server-autoupdate.log"

# Identify server
HOSTNAME=$(hostname)

echo "=== Update Started: $(date) ===" >> "$LOG_FILE"
echo "Host: $HOSTNAME" >> "$LOG_FILE"

# Do not automatically patch Proxmox hypervisors
if command -v pveversion >/dev/null 2>&1; then
    echo "Proxmox VE detected - automatic updates skipped." >> "$LOG_FILE"
    echo "Update Result: SKIPPED" >> "$LOG_FILE"
    echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    exit 0
fi

# Detect Ubuntu / Debian
if [ -f /etc/debian_version ]; then

    export DEBIAN_FRONTEND=noninteractive

    # Refresh package repositories
    if apt-get update >> "$LOG_FILE" 2>&1; then
        echo "Repository Refresh: SUCCESS" >> "$LOG_FILE"
    else
        echo "Repository Refresh: FAILED" >> "$LOG_FILE"
        echo "Package Upgrade: NOT RUN" >> "$LOG_FILE"
        echo "Update Result: FAILED" >> "$LOG_FILE"
        echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        exit 1
    fi

    # Install available upgrades
    if apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
        echo "Package Upgrade: SUCCESS" >> "$LOG_FILE"
    else
        echo "Package Upgrade: FAILED" >> "$LOG_FILE"
        echo "Update Result: FAILED" >> "$LOG_FILE"
        echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        exit 1
    fi

    # Clean package cache
    if apt-get clean >> "$LOG_FILE" 2>&1; then
        echo "APT Cache Cleanup: SUCCESS" >> "$LOG_FILE"
    else
        echo "APT Cache Cleanup: FAILED" >> "$LOG_FILE"
    fi

else
    echo "Unsupported OS distribution." >> "$LOG_FILE"
    echo "Update Result: FAILED" >> "$LOG_FILE"
    echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    exit 1
fi

# Check whether packages remain upgradeable
UPGRADEABLE_COUNT=$(apt list --upgradeable 2>/dev/null | tail -n +2 | wc -l)

echo "Packages Remaining Upgradeable: $UPGRADEABLE_COUNT" >> "$LOG_FILE"

if [ "$UPGRADEABLE_COUNT" -gt 0 ]; then
    echo "Remaining Upgradeable Packages:" >> "$LOG_FILE"
    apt list --upgradeable 2>/dev/null | tail -n +2 >> "$LOG_FILE"
fi

# Check whether a reboot is required
if [ -f /var/run/reboot-required ]; then
    echo "Reboot Required: YES" >> "$LOG_FILE"

    if [ -f /var/run/reboot-required.pkgs ]; then
        echo "Reboot-triggering packages:" >> "$LOG_FILE"
        cat /var/run/reboot-required.pkgs >> "$LOG_FILE"
    fi
else
    echo "Reboot Required: NO" >> "$LOG_FILE"
fi

echo "Update Result: SUCCESS" >> "$LOG_FILE"
echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

exit 0
```

---

# Script Permissions

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/sys-update.sh
```

Verify:

```bash
ls -l /usr/local/bin/sys-update.sh
```

Expected:

```text
-rwxr-xr-x
```

---

# Bash Syntax Validation

Before executing a modified script:

```bash
sudo bash -n /usr/local/bin/sys-update.sh
```

No output indicates that Bash found no syntax errors.

This does not prove that the script logic is correct. It validates syntax only.

---

# Manual Execution

Execute:

```bash
sudo /usr/local/bin/sys-update.sh
```

Immediately check the script exit code:

```bash
echo $?
```

Expected successful result:

```text
0
```

---

# Log Verification

Inspect recent update activity:

```bash
sudo tail -40 /var/log/server-autoupdate.log
```

Successful canary output:

```text
Host: locator01

Repository Refresh: SUCCESS
Package Upgrade: SUCCESS
APT Cache Cleanup: SUCCESS
Packages Remaining Upgradeable: 0
Reboot Required: NO
Update Result: SUCCESS
```

---

# Package Verification

An administrator should not assume that a successful `apt-get upgrade` means no packages remain.

Check:

```bash
apt list --upgradeable
```

This verification was incorporated into the automated script.

The script records:

```text
Packages Remaining Upgradeable: 0
```

or identifies the remaining packages when the count is greater than zero.

---

# Kernel Update Investigation

During initial testing, the following packages remained upgradeable:

```text
linux-generic
linux-headers-generic
linux-image-generic
```

Package policy was investigated with:

```bash
apt-cache policy linux-generic linux-headers-generic linux-image-generic
```

A simulated dependency-aware upgrade was then performed:

```bash
sudo apt-get -s dist-upgrade
```

The simulation reported:

```text
3 upgraded
7 newly installed
0 to remove
0 not upgraded
```

The pending kernel upgrade required additional version-specific kernel packages.

This explained why:

```bash
apt-get upgrade
```

did not initially install the kernel update.

---

# Kernel Metapackage Behavior

The `linux-generic` package acts as a metapackage.

Conceptually:

```text
linux-generic
      |
      +--> linux-image-generic
      |         |
      |         +--> versioned kernel image
      |
      +--> linux-headers-generic
                |
                +--> versioned kernel headers
```

Updating the metapackage caused APT to resolve and install the required kernel image, modules, headers, and tools.

---

# Installed Kernel vs Running Kernel

After installation:

```bash
dpkg -l | grep -E 'linux-image-[0-9].*-generic' | awk '{print $2, $3}'
```

reported:

```text
linux-image-7.0.0-29-generic 7.0.0-29.29
linux-image-7.0.0-30-generic 7.0.0-30.30
```

However:

```bash
uname -r
```

still reported:

```text
7.0.0-29-generic
```

This demonstrated an important distinction:

```text
Kernel installed on disk
          !=
Kernel currently executing
```

The new kernel becomes active during the next boot.

---

# Reboot Detection

Ubuntu creates:

```text
/var/run/reboot-required
```

when a reboot is required.

Check manually:

```bash
test -f /var/run/reboot-required && echo "REBOOT REQUIRED" || echo "NO REBOOT REQUIRED"
```

Packages responsible for requesting the reboot can be examined with:

```bash
cat /var/run/reboot-required.pkgs
```

During testing:

```text
linux-image-7.0.0-30-generic
linux-base
```

requested a reboot.

---

# Post-Reboot Verification

After reboot:

```bash
uname -r
```

returned:

```text
7.0.0-30-generic
```

The reboot flag was then checked:

```bash
test -f /var/run/reboot-required && echo "REBOOT REQUIRED" || echo "NO REBOOT REQUIRED"
```

Result:

```text
NO REBOOT REQUIRED
```

The kernel update lifecycle was therefore successfully completed.

---

# SMTP Email Reporting Infrastructure

A lightweight SMTP client was selected instead of operating a full mail server.

Installed packages:

```bash
sudo apt update
sudo apt install msmtp msmtp-mta -y
```

Version validation:

```bash
msmtp --version
```

Installed version during testing:

```text
msmtp 1.8.32
```

---

# SMTP Architecture

```text
locator01
    |
    v
sys-update.sh
    |
    v
msmtp
    |
    | TLS / authenticated SMTP
    v
smtp.gmail.com
    |
    v
4techworks@gmail.com
    |
    | Internet mail delivery
    v
support@4techworks.com
    |
    v
Administrator
```

The sending and receiving mail providers do not need to be the same.

Gmail provides outbound SMTP relay.

The `support@4techworks.com` mailbox receives the resulting message through its own mail provider.

---

# SMTP Configuration

System configuration:

```text
/etc/msmtprc
```

Configuration structure:

```ini
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account        gmail
host           smtp.gmail.com
port           587
from           4techworks@gmail.com
user           4techworks@gmail.com
password       APP_PASSWORD

account default : gmail
```

## Security Requirement

The actual App Password must never be stored in Git documentation.

The production `/etc/msmtprc` contains the credential and is protected with:

```bash
sudo chown root:root /etc/msmtprc
sudo chmod 600 /etc/msmtprc
```

Verified:

```text
-rw------- root root /etc/msmtprc
```

Only root can read or modify the configuration.

---

# SMTP Authentication

Google 2-Step Verification was enabled for the sending account.

A dedicated Google App Password was created for:

```text
Techworks Linux Lab
```

The normal Google account password is not stored on the Linux server.

---

# Manual SMTP Test

A manual email was generated using `printf` and piped into `msmtp`.

Conceptually:

```text
printf
   |
   | message contents
   v
msmtp
   |
   v
Gmail SMTP
   |
   v
support@4techworks.com
```

The test email was successfully delivered.

This proved:

```text
locator01 -> Internet connectivity       PASS
locator01 -> smtp.gmail.com              PASS
TLS negotiation                          PASS
SMTP authentication                      PASS
Google App Password                      PASS
Outbound SMTP submission                 PASS
Internet email routing                   PASS
Destination mailbox delivery             PASS
```

---

# Security Controls

Do not commit:

```text
/etc/msmtprc
Google App Password
Normal Gmail password
SMTP credentials
Other secrets
```

Git should contain templates and documentation only.

Example:

```text
Git
 |
 +-- sys-update.sh
 |
 +-- msmtprc.example
 |
 +-- RB-009...
```

Production credentials remain outside source control.

---

# Current Patch Workflow

```text
START
  |
  v
Identify hostname
  |
  v
Proxmox?
 /     \
YES     NO
 |       |
SKIP   Debian?
         |
        YES
         |
         v
  apt-get update
         |
     success?
      /    \
    NO      YES
    |        |
   FAIL   apt-get upgrade
             |
          success?
           /    \
         NO      YES
         |        |
        FAIL   apt clean
                  |
                  v
          Check upgradeable
                  |
                  v
          Check reboot state
                  |
                  v
             Write result
                  |
                  v
                END
```

---

# Future Email Report

The update script will eventually generate a concise message similar to:

```text
Subject:
[PATCH][locator01] SUCCESS

Host: locator01
Repository Refresh: SUCCESS
Package Upgrade: SUCCESS
APT Cache Cleanup: SUCCESS
Packages Remaining Upgradeable: 0
Reboot Required: NO
Update Result: SUCCESS
```

---

# Future Living-Lab Integration

The SMTP infrastructure will also support automated Linux administration tickets.

Planned architecture:

```text
             Linux Lab
                 |
       +---------+---------+
       |                   |
 Patch Reports        Incident Generator
       |                   |
       |               Create incident
       |                   |
       |               Ticket ID
       |                   |
       +---------+---------+
                 |
               msmtp
                 |
                 v
        support@4techworks.com
                 |
                 v
           Linux Administrator
                 |
                 v
              TRIAGE
                 |
            INVESTIGATE
                 |
              RESOLVE
                 |
              VERIFY
                 |
             DOCUMENT
                 |
               CLOSE
```

---

# Lessons Learned

## Successful command does not mean fully patched

A successful:

```bash
apt-get upgrade
```

does not guarantee:

```text
0 packages remaining
```

Always verify the resulting state.

---

## Installed does not mean running

A newly installed kernel does not replace the kernel currently executing in memory.

Verify both:

```bash
dpkg -l
```

and:

```bash
uname -r
```

---

## Simulation before change

Before allowing APT to perform broader dependency changes:

```bash
sudo apt-get -s dist-upgrade
```

was used to determine what APT intended to change.

This follows the administrative principle:

```text
Observe
   |
Simulate
   |
Understand
   |
Change
   |
Verify
```

---

## Code and logs are different operational objects

```text
/usr/local/bin/sys-update.sh
```

contains the automation logic.

```text
/var/log/server-autoupdate.log
```

contains evidence of what actually happened.

A valid script does not prove successful execution.

---

## Source control and secrets must remain separate

```text
CODE       -> Git
CONFIG     -> Git when safe
SECRETS    -> outside Git
RUNTIME    -> local server
LOGS       -> operational logging
```

---

# Current Status

Completed:

```text
[✓] Create Ubuntu/Debian update script
[✓] Add Proxmox exclusion
[✓] Add hostname identification
[✓] Add persistent logging
[✓] Add repository-refresh validation
[✓] Add package-upgrade validation
[✓] Add APT cache cleanup
[✓] Add remaining-package detection
[✓] Investigate kept-back kernel packages
[✓] Understand kernel metapackages
[✓] Add reboot-required detection
[✓] Identify reboot-triggering packages
[✓] Complete kernel upgrade
[✓] Reboot canary server
[✓] Verify new running kernel
[✓] Verify reboot flag cleared
[✓] Install msmtp
[✓] Configure TLS SMTP
[✓] Configure Google App Password
[✓] Protect SMTP credential
[✓] Test external SMTP delivery
[✓] Validate locator01 as canary
```

Pending:

```text
[ ] Integrate SMTP reporting into sys-update.sh
[ ] Generate structured email subject/body
[ ] Test automated patch email
[ ] Add script to Git
[ ] Establish Git source of truth
[ ] Add ShellCheck
[ ] Create CI validation pipeline
[ ] Introduce Ansible
[ ] Deploy script to additional Linux servers
[ ] Build CD deployment workflow
[ ] Create separate Proxmox patch procedure
```

---

# Next Phase

```text
RB-009
   |
   +--> SMTP integration
   |
   +--> Git
   |
   +--> CI
   |
   +--> Ansible
   |
   +--> CD
```

After RB-009 is completed, configure and validate backups for `locator01` to the external backup storage.

---


