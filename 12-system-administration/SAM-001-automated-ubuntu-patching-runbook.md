## SAM-001 — Automated Ubuntu Package Updates with Cron

**System:** `ubuntu-devops01`  
**OS:** Ubuntu 24.04.4 LTS  
**Date:** 2026-09-08  
**Status:** Complete / Verified

### Objective

Configure `ubuntu-devops01` to perform routine Ubuntu package updates automatically once per week while retaining manual control over reboots and higher-risk maintenance operations.

### Initial Problem

The existing update script was not executing manually:

```text
-bash: ./auto_update: cannot execute: required file not found
```

The script contained an invalid shebang:

```bash
#! bin/bash
```

Corrected to:

```bash
#!/bin/bash
```

This restored script execution.

### APT Repository Failure

After fixing the script, `apt-get update` failed against the Ookla Speedtest repository:

```text
https://packagecloud.io/ookla/speedtest-cli/ubuntu noble Release
404 Not Found
```

The repository configuration was located with:

```bash
grep -R "packagecloud.io/ookla" \
/etc/apt/sources.list \
/etc/apt/sources.list.d/ 2>/dev/null
```

Result:

```text
/etc/apt/sources.list.d/ookla_speedtest-cli.list
```

The invalid repository was disabled rather than deleted:

```bash
sudo mv /etc/apt/sources.list.d/ookla_speedtest-cli.list \
/etc/apt/sources.list.d/ookla_speedtest-cli.list.disabled
```

APT repository health was then verified:

```bash
sudo apt-get update
```

Result: **Successful with no repository errors.**

### Package Upgrade Investigation

Available packages were identified with:

```bash
apt list --upgradeable
```

A normal upgrade was performed:

```bash
sudo apt-get upgrade -y
```

Terraform and `dnsmasq-base` were successfully upgraded.

Several Ubuntu packages were deferred due to **phased updates**, while `linux-firmware` was kept back.

The firmware package was investigated with:

```bash
apt-cache policy linux-firmware
```

A simulated dependency-changing upgrade was then performed:

```bash
sudo apt-get dist-upgrade --simulate
```

The simulation showed that the new `linux-firmware` packaging required installation of 18 additional hardware-specific firmware packages.

No packages were removed.

The established manual procedure for this package remains:

```bash
sudo apt-get install linux-firmware
```

### Kernel Update and Reboot

`needrestart` identified a pending kernel transition:

```text
Running kernel:
6.8.0-138-generic

Expected kernel:
6.8.0-139-generic
```

A controlled reboot was performed.

After reboot:

```bash
uname -r
```

Result:

```text
6.8.0-139-generic
```

Systemd health was checked:

```bash
systemctl --failed
```

Result:

```text
0 loaded units listed.
```

Docker workload recovery was checked:

```bash
docker ps
```

All expected containers returned to an `Up` state, including:

- Glance
- Grafana
- Prometheus
- Alertmanager
- Blackbox Exporter
- SNMP Exporter
- Node Exporter
- UniFi Network Application
- UniFi MongoDB
- Portainer

### Automated Update Script

Script location:

```text
/home/brettcoder/scripts/bash_scripts/auto_update
```

Recommended script:

```bash
#!/bin/bash

/usr/bin/apt-get update &&
/usr/bin/apt-get upgrade --with-new-pkgs -y
```

The script is intentionally run as `root` through cron rather than relying on interactive `sudo` authentication.

Automatic rebooting is **not** included.

### Root Cron Configuration

Root's crontab was configured using:

```bash
sudo crontab -e
```

Production schedule:

```cron
0 3 * * 0 /home/brettcoder/scripts/bash_scripts/auto_update >> /var/log/auto_update.log 2>&1
```

Schedule interpretation:

```text
Minute:       0
Hour:         3
Day:          any
Month:        any
Day of week:  Sunday
```

Therefore:

> **Run every Sunday at 03:00 system local time.**

Both stdout and stderr are appended to:

```text
/var/log/auto_update.log
```

### Cron Functional Test

The schedule was temporarily changed to execute every minute:

```cron
* * * * * /home/brettcoder/scripts/bash_scripts/auto_update >> /var/log/auto_update.log 2>&1
```

Execution was verified using:

```bash
sudo tail -30 /var/log/auto_update.log
```

APT repository activity appeared in the log, proving successful execution through the complete chain:

```text
cron
  ↓
root crontab
  ↓
auto_update
  ↓
apt-get update/upgrade
  ↓
/var/log/auto_update.log
```

The production Sunday schedule was subsequently restored.

### Final Verification

Installed root crontab:

```bash
sudo crontab -l
```

Confirmed:

```cron
0 3 * * 0 /home/brettcoder/scripts/bash_scripts/auto_update >> /var/log/auto_update.log 2>&1
```

Cron daemon:

```bash
systemctl status cron --no-pager
```

Result:

```text
Loaded: loaded
Active: active (running)
```

The system journal additionally recorded successful root cron executions:

```text
(root) CMD (/home/brettcoder/scripts/bash_scripts/...)
pam_unix(cron:session): session opened for user root
pam_unix(cron:session): session closed for user root
```

**Final status: VERIFIED OPERATIONAL**

### Operational Policy

Routine package upgrades are automated weekly. Ubuntu phased updates are allowed to follow Canonical's rollout schedule rather than being forced. Dependency-safe package additions may be handled with `--with-new-pkgs`.

Firmware/package transitions can be reviewed manually when appropriate:

```bash
sudo apt-get install linux-firmware
```

Kernel and other reboot-required updates **do not trigger an automatic reboot**. Reboots remain controlled maintenance operations followed by:

```bash
uname -r
systemctl --failed
docker ps
```

### Lessons Learned

A script can exist and have execute permission while still failing because its shebang references an invalid interpreter path. APT repository failures can prevent an otherwise valid update script from progressing when commands are chained with `&&`.

`apt-get upgrade` deliberately behaves conservatively. “Deferred due to phasing” and “kept back” are not equivalent conditions and should be investigated rather than automatically overridden.

Cron jobs also execute within a specific security context. A root crontab is preferable to embedding interactive `sudo` operations inside an unattended user cron job.

Finally, configuration is not the same as verification. Temporarily executing the actual cron workload and observing `/var/log/auto_update.log` demonstrated that the **entire automation path** works.

### Suggested Git commit

```bash
git add .
git commit -m "Add SAM-001 automated Ubuntu patching runbook"
git push
```

Suggested filename:

```text
SAM-001-automated-ubuntu-package-updates-with-cron.md
```

This one is worth keeping in the KB. It documents not merely *how to write a cron expression*, but an actual patch-management troubleshooting workflow from initial failure through verified unattended execution.