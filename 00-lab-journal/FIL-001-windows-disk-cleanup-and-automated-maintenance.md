# FIL-001: Windows Disk Cleanup and Automated Maintenance

| Field | Value |
|---|---|
| Runbook ID | FIL-001 |
| Category | Filesystem / Storage |
| Platform | Windows 11 / Windows PowerShell 5.1 |
| Computer | `4TECHWORKS2` |
| Managed profile | `C:\Users\brett.TECHWORKS` |
| Script | `C:\Scripts\DiskMaintenance\Invoke-DiskMaintenance.ps1` |
| Status | Implemented and verified |
| Last verified | 2026-08-27 |

## Purpose

Document the investigation, controlled cleanup, verification, and ongoing automation used to reclaim space on the Windows system drive while protecting personal data, Windows-managed files, and active application storage.

## Scope

This runbook covers:

- Storage investigation with WinDirStat and read-only PowerShell inventories.
- Decommissioning obsolete VirtualBox, VMware, Vagrant, Hyper-V/BYOL, import, and Windows evaluation artifacts.
- Review of OneDrive Known Folder Backup and synchronized storage.
- Conservative cleanup of Downloads and temporary files using retention rules.
- Reporting, but not automatic deletion, of large VM and image files.
- Recommended monthly execution through Windows Task Scheduler.

This runbook does not authorize broad deletion from Documents, Pictures, Desktop, Windows system directories, Program Files, application-managed virtual disks, or OneDrive without explicit review.

## Environment

- System drive capacity observed: **930.45 GB**.
- Initial storage condition: approximately **912 GB used**, leaving roughly **18 GB free**.
- Early post-cleanup baseline: **779.99 GB used / 150.46 GB free (16.2% free)**.
- Final successful automation test baseline: **593.13 GB free**.
- OneDrive root reviewed: `C:\Users\brett\OneDrive`.
- New profile under maintenance: `C:\Users\brett.TECHWORKS`.
- Script runtime requirement: Windows PowerShell **5.1 or later**.

## Initial Problem

The C: drive had accumulated years of local lab infrastructure, virtual disks, exported appliances, installation media, synchronized OneDrive content, evaluation packages, and temporary data. The initial proposal to delete files solely because they were more than two years old was rejected after investigation showed that timestamps were not a reliable indicator of value or safety.

The goal became:

1. Identify the largest storage consumers.
2. Confirm ownership and purpose before deletion.
3. Retire the obsolete lab estate in bounded groups.
4. Preserve personal and professionally valuable material.
5. Automate only low-risk cleanup with explicit retention periods.

## Investigation with WinDirStat

WinDirStat was used to identify large directories and file types, then refreshed after each major deletion so stale scan data was not mistaken for current usage. PowerShell was used to measure candidate directories, verify deletion with `Test-Path`, and establish new C: drive baselines.

Important WinDirStat findings included:

| File type or location | Observed size | Interpretation |
|---|---:|---|
| `.vdi` files | 230.7 GB / 14 files | Predominantly obsolete VirtualBox disks |
| `.vmdk` files | 93.9 GB / 71 files | VMware/VirtualBox disk content requiring path review |
| `.iso` files | Up to 83.6 GB initially | Evaluation and installation media requiring review |
| `.ova` files | 79.6 GB initially | Exported virtual appliances |
| `C:\Users\brett\VirtualBox VMs` | 214.43 GB measured | Retired VirtualBox estate |
| `C:\WinEvalCenter` | About 34 GB | Expiring/obsolete Windows evaluation material |
| OneDrive Desktop | 125.52 GB | Historical content remaining after Desktop backup was disabled |

Recursive Windows PowerShell enumeration sometimes raised `PathTooLongException` because of legacy path-length limits. WinDirStat and targeted measurements provided sufficient independent evidence, and deletion success was verified directly afterward.

## OneDrive Findings

OneDrive Known Folder Backup was configured appropriately for the intended policy:

- Documents: backed up, approximately **40.8 GB**.
- Pictures: backed up, approximately **317 GB**.
- Desktop: not backed up.
- Music and Videos: not backed up.
- Total OneDrive content shown: approximately **487.1 GB**.

Although Desktop backup was off, `OneDrive\Desktop` still contained approximately **125.52 GB** of historical data from earlier use. Disabling Known Folder Backup does not remove previously synchronized content.

The `brett.TECHWORKS` profile was newly created, but it displayed older file dates because OneDrive restored existing content into it. Dates of **12/31/1969** were Unix epoch/timestamp artifacts, not evidence that the profile or files were genuinely that old. The exported inventory contained **5,609** such files totaling only about **301 MB**.

Operational conclusions:

- Do not delete `C:\Users\brett.TECHWORKS` based on apparent age.
- Treat deletion inside OneDrive as a cloud-synchronized deletion.
- Keep the OneDrive recycle bin intact until cleanup verification is complete.
- Use OneDrive primarily for intentionally saved Documents, Pictures, and personal files.
- Keep VM disks, ISO files, exports, installers, Downloads, and temporary lab data outside OneDrive.
- Enable or retain Files On-Demand so older Pictures do not all need to remain hydrated on C:.

## Major Cleanup Targets and Reclaimed Space

The following targets were reviewed and removed after the user confirmed that the old virtualization and evaluation estate was no longer required.

| Target | Measured/logical size | Result |
|---|---:|---|
| `C:\Users\brett\OneDrive\Desktop\BYOL_Image` | 83.87 GB | Removed; synchronized OneDrive deletion |
| `C:\Users\brett\OneDrive\Desktop\VMs` | 36.63 GB | Removed; synchronized OneDrive deletion |
| `C:\Users\brett\VirtualBox VMs` | 214.43 GB | Removed; `Test-Path` returned `False` |
| `C:\Users\brett\OneDrive\Documents\Virtual Machines` | 39.89 GB | Removed; `Test-Path` returned `False` |
| `C:\WinEvalCenter` | About 34 GB | Removed; `Test-Path` returned `False` |
| `C:\Users\brett\.vagrant.d\boxes` | 31.68 GB | Removed as obsolete lab infrastructure |
| `C:\import` | 6.34 GB | Removed as obsolete import content |

A later five-target inventory under the active/new profile identified **198.41 GB** of logical content across BYOL images, OneDrive VMs, VMware VMs, Vagrant boxes, and `C:\import`. These logical sizes must not be summed directly with physical recovery: synchronized paths could overlap, and OneDrive files could be cloud-only or partially hydrated.

Verified storage milestones included:

- After the first OneDrive lab cleanup: **779.99 GB used / 150.46 GB free**; approximately **132 GB** recovered from the earlier baseline.
- After removing `C:\Users\brett\VirtualBox VMs`: **565.57 GB used / 364.88 GB free**; approximately **214.4 GB** recovered in that operation.
- After removing the VMware directory: **525.73 GB used / 404.73 GB free**.
- After removing `C:\WinEvalCenter`: **491.73 GB used / 438.72 GB free**, approximately **420 GB recovered** from the original used-space baseline at that stage.
- Later verified baseline: **453.72 GB used / 476.73 GB free (51.2% free)**.
- First automation test: **4.62 GB recovered**, increasing free space from **589.76 GB** to **594.38 GB** by deleting 3,299 user Temp files (2.81 GB) and 753 Windows Temp files (1.80 GB).
- Final corrected-profile test: **593.13 GB free before and after**, with no eligible Downloads or profile Temp files and one zero-rounded-size Windows Temp file removed.

Small baseline differences between tests are normal because Windows, applications, updates, caches, and paging activity continue to change disk usage.

## Items Deliberately Preserved

- Documents, Pictures, and ordinary Desktop content.
- `C:\System Volume Information` and Windows restore/shadow-copy data.
- `C:\pagefile.sys`.
- The Claude-managed `rootfs.vhdx` (reported at **8.38 GB**) because it is application-managed storage.
- A **22.8 GB** Radeon recording that may document an AWS TechU capstone or client demonstration; retain or archive rather than delete solely because of size.
- Current Kali Linux 2026.2 media, including the **24.69 GB** VDI, pending deliberate review.
- Personal videos and possible duplicate OneDrive/phone-sync representations until their physical-storage behavior and value are confirmed.

## Safe-Retention Policy

| Location or class | Policy |
|---|---|
| `C:\Users\brett.TECHWORKS\Downloads` | Delete files older than **90 days** |
| `C:\Users\brett.TECHWORKS\AppData\Local\Temp` | Delete files older than **30 days** |
| `C:\Windows\Temp` | Delete files older than **30 days** |
| VM/image extensions (`.iso`, `.ova`, `.ovf`, `.vdi`, `.vmdk`, `.vhd`, `.vhdx`) | **Report only** when at least **5 GB**; never auto-delete |
| Documents, Pictures, Desktop | Protected; no automated deletion |
| Windows and Program Files directories | Protected; no automated deletion |

The policy is based on location, file class, and operational value—not file age alone. “Old timestamp” does not mean “obsolete.”

## Final PowerShell Script

Script path:

```text
C:\Scripts\DiskMaintenance\Invoke-DiskMaintenance.ps1
```

The final script:

- Requires Windows PowerShell 5.1.
- Explicitly sets `$ManagedProfile` to `C:\Users\brett.TECHWORKS`.
- Aborts with a fatal log entry if the managed profile does not exist.
- Records the computer, execution user, managed profile, and C: free space.
- Recursively deletes eligible files from the three approved cleanup locations.
- Removes only empty directories after eligible file deletion.
- Retains non-empty or inaccessible directories.
- Continues past individual file errors and logs each failure.
- Reports qualifying VM/image files of at least 5 GB without deleting them.
- Records free space before, free space after, and recovered space.

Explicitly configuring the managed profile is essential. The first script version used `$env:USERPROFILE` and `$env:TEMP`, which maintained `C:\Users\brett`. A scheduled task running as `SYSTEM` would otherwise target the Windows system profile. The corrected script consistently maintains `C:\Users\brett.TECHWORKS`, independent of the execution account.

## Verification Output

Final successful test command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\DiskMaintenance\Invoke-DiskMaintenance.ps1"
```

Key output from 2026-08-27:

```text
TechWorks Disk Maintenance started
Computer: 4TECHWORKS2
Execution user: brett
Managed profile: C:\Users\brett.TECHWORKS
Free space before: 593.13 GB

SCAN | C:\Users\brett.TECHWORKS\Downloads | Retention: 90 days
OK | No eligible files: C:\Users\brett.TECHWORKS\Downloads

SCAN | C:\Users\brett.TECHWORKS\AppData\Local\Temp | Retention: 30 days
OK | No eligible files: C:\Users\brett.TECHWORKS\AppData\Local\Temp

SCAN | C:\Windows\Temp | Retention: 30 days
DELETE | 1 files | 0 GB | C:\Windows\Temp

Scanning managed profile for large VM/image files (REPORT ONLY).
REPORT | 24.69 GB | C:\Users\brett.TECHWORKS\Downloads\kali-linux-2026.2-virtualbox-amd64\kali-linux-2026.2-virtualbox-amd64\kali-linux-2026.2-virtualbox-amd64.vdi

Maintenance completed
Free space before: 593.13 GB
Free space after:  593.13 GB
Space recovered:   0 GB
```

This verifies the intended profile, retention periods, protected handling of large images, and successful completion.

## Logs

Log root:

```text
C:\ProgramData\TechWorks\DiskMaintenance\Logs
```

The script creates timestamped logs using the intended naming pattern:

```text
C:\ProgramData\TechWorks\DiskMaintenance\Logs\DiskMaintenance-yyyy-MM-dd_HHmmss.log
```

The final console output displayed:

```text
C:\ProgramData\TechWorks\DiskMaintenance\Logs\DiskMaintenance-2026-08-27\_084456.log
```

Confirm the deployed script uses `Get-Date -Format "yyyy-MM-dd_HHmmss"` so the underscore remains part of the filename rather than being interpreted as a directory separator.

## Scheduling Recommendation

Create a Windows Task Scheduler task with these settings:

- Name: `TechWorks Disk Maintenance`.
- Trigger: Monthly, during a low-usage maintenance window.
- Program: `powershell.exe`.
- Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\DiskMaintenance\Invoke-DiskMaintenance.ps1"`.
- Run with highest privileges so `C:\Windows\Temp` can be maintained.
- Run whether the user is logged on or not.
- Use a service account or `SYSTEM` only after confirming the explicit `$ManagedProfile` remains set to `C:\Users\brett.TECHWORKS`.
- Start the task only when the computer is on AC power, if appropriate for the workstation.
- Stop the task if it exceeds a reasonable maintenance window, such as two hours.
- Retain Task Scheduler history and review the script log after the first scheduled execution.

Run one manual test after task creation and confirm that the task’s last result is `0x0`, the managed-profile log line is correct, and a timestamped log was created.

## Safeguards

1. Inventory and measure a target before any destructive action.
2. Close VirtualBox, VMware, Hyper-V, Vagrant terminals, and related applications before removing VM directories.
3. Use `-LiteralPath` for exact deletion targets.
4. Verify each major deletion with `Test-Path` and a fresh `Get-PSDrive C` reading.
5. Refresh WinDirStat after major deletions; do not act on stale scan data.
6. Treat OneDrive paths as cloud-connected and preserve the OneDrive recycle bin during the verification window.
7. Never delete an entire user profile because synchronized files have old timestamps.
8. Never manually delete application-managed virtual disks while the application remains installed and active.
9. Keep personal media and professionally valuable recordings unless explicitly classified for removal.
10. Keep VM/image automation report-only; require human review before deletion.
11. Log errors per file and continue so one locked file does not abort the maintenance run.
12. Review retention values and the managed-profile path whenever accounts or storage architecture change.

## Lessons Learned

- Storage cleanup is safest when treated as infrastructure decommissioning, not an age-based purge.
- File timestamps can reflect synchronization history, archive metadata, or Unix epoch artifacts; they are not sufficient deletion criteria.
- Logical folder totals and physical disk recovery differ when OneDrive Files On-Demand or duplicated synchronized paths are involved.
- Active VM disks do not belong in general-purpose synchronization folders.
- A newly created Windows profile may surface years-old content through OneDrive.
- WinDirStat is effective for locating large file classes, but it must be rescanned after deletions.
- `Test-Path`, drive-space measurements, and logs provide better completion evidence than a deletion command alone.
- Scheduled scripts must not rely on `$env:USERPROFILE` or `$env:TEMP` when they are intended to maintain a specific user profile.
- Conservative automation should delete only approved disposable data and report ambiguous high-value files for review.

## Command Reference

Check drive utilization:

```powershell
Get-PSDrive C | Select-Object `
    @{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}},
    @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}},
    @{N='TotalGB';E={[math]::Round(($_.Used + $_.Free)/1GB,2)}},
    @{N='PercentFree';E={[math]::Round(($_.Free / ($_.Used + $_.Free)) * 100,1)}}
```

Measure a candidate directory:

```powershell
$Target = "C:\path\to\candidate"
$Size = (Get-ChildItem -LiteralPath $Target -File -Recurse -Force -ErrorAction SilentlyContinue |
    Measure-Object Length -Sum).Sum
"{0:N2} GB | {1}" -f ($Size / 1GB), $Target
```

Verify a removed path:

```powershell
Test-Path -LiteralPath "C:\path\to\removed-target"
```

List the 50 largest files on C: for review:

```powershell
Get-ChildItem C:\ -File -Recurse -Force -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 50 `
        @{N='SizeGB';E={[math]::Round($_.Length / 1GB,2)}},
        LastWriteTime,
        FullName |
    Format-Table -AutoSize
```

Run maintenance manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\DiskMaintenance\Invoke-DiskMaintenance.ps1"
```

Review recent logs:

```powershell
Get-ChildItem -LiteralPath "C:\ProgramData\TechWorks\DiskMaintenance\Logs" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 Name, Length, LastWriteTime, FullName
```

## Git Commit Message

```text
docs(fil): add Windows disk cleanup and maintenance runbook

Document WinDirStat investigation, OneDrive findings, retired VM and
evaluation storage, safe retention policy, PowerShell automation,
verification evidence, logging, safeguards, and scheduling guidance.
```
