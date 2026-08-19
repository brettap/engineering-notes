[200~# RB-0007 — Disk Capacity, Filesystem & LVM Incident Troubleshooting

## Purpose

Practice L2 Linux administration and incident response for storage-capacity problems.

This lab covers:

* Block-device discovery
* Filesystem and mount-point identification
* LVM architecture
* Filesystem capacity monitoring
* Disk-usage investigation
* Large-file discovery
* Process-to-file relationships
* Safe remediation decisions
* Deleted-but-open files
* `df` versus `du`
* File descriptors and inode behavior
* Linux process states and signals
* Zombie processes
* Post-remediation application verification
* Root-cause analysis

---

# Environment

| Component                     | Value                               |
| ----------------------------- | ----------------------------------- |
| Host                          | `devops02`                          |
| Primary disk                  | `/dev/sda`                          |
| Disk capacity                 | 200 GB                              |
| Root filesystem               | ext4                                |
| Root logical volume           | `/dev/mapper/ubuntu--vg-ubuntu--lv` |
| Volume group                  | `ubuntu-vg`                         |
| Logical volume                | `ubuntu-lv`                         |
| Lab image                     | `/opt/noc-lab/storage-lab.img`      |
| Lab block device              | `/dev/loop0`                        |
| Lab filesystem                | ext4                                |
| Lab mount                     | `/mnt/noc-storage`                  |
| Test log directory            | `/mnt/noc-storage/app-logs`         |
| Production-style test service | `noc-app.service`                   |
| Application health log        | `/var/log/noc-app.log`              |

---

# 1. Incident Scenario

```text
INCIDENT: INC-LNX-007
HOST:     devops02
SEVERITY: HIGH
CATEGORY: Storage / Filesystem

ALERT:
Filesystem utilization has exceeded
the critical threshold.

IMPACT:
Application writes may fail if available
capacity continues decreasing.

ASSIGNMENT:
1. Identify the affected filesystem.
2. Determine what is consuming capacity.
3. Identify responsible directories/files.
4. Determine whether data can safely be removed.
5. Remediate capacity.
6. Verify filesystem recovery.
7. Verify noc-app functionality.
8. Document root cause.
```

Operational workflow:

```text
STORAGE ALERT
      │
      ▼
Which filesystem is constrained?
      │
      ▼
Where is capacity being consumed?
      │
      ▼
Which directory?
      │
      ▼
Which files?
      │
      ▼
Why are they growing?
      │
      ▼
Are they actively being used?
      │
      ▼
Can they safely be removed,
truncated, rotated, or archived?
      │
      ▼
Remediate
      │
      ▼
Verify capacity
      │
      ▼
Verify application
      │
      ▼
RCA
```

---

# 2. Establish Storage Baseline

## Identify mounted filesystems

```bash
findmnt
```

### Purpose

Displays the filesystem mount hierarchy, including:

* Source device
* Mount point
* Filesystem type
* Mount options

Example mounts discovered included:

```text
/
/boot
/boot/efi
/var
/proc
/sys
/dev
/run
```

---

## Filesystem capacity

```bash
df -h
```

### Purpose

Displays filesystem-level capacity.

`-h` provides human-readable sizes.

Important columns:

```text
Filesystem
Size
Used
Avail
Use%
Mounted on
```

Initial root filesystem utilization was approximately:

```text
/ = 8–10% utilized
~83–100 GB available
```

---

# 3. Verify Application Baseline

Check service:

```bash
systemctl status noc-app
```

Then verify actual application functionality:

```bash
sudo tail -n 5 /var/log/noc-app.log
```

The timestamps continued advancing every ten seconds.

This established:

```text
SYSTEM BASELINE
      │
      ├── Storage healthy
      │
      ├── Filesystems mounted
      │
      ├── Capacity available
      │
      └── noc-app functionally healthy
```

---

# 4. Block Device Discovery

Run:

```bash
lsblk
```

### Purpose

Displays block devices and their relationships.

The server contained:

```text
sda       200G
│
├── sda1    ~1G
├── sda2     2G
└── sda3 196.9G
```

Correct mount relationships:

```text
/dev/sda1 → /boot/efi
/dev/sda2 → /boot
```

However, `/` was **not directly mounted from `/dev/sda3`**.

Instead, LVM was present.

---

# 5. Storage Layer Model

The complete storage stack was:

```text
BLOCK DEVICE
/dev/sda
200 GB
      │
      ▼
PARTITION
/dev/sda3
196.9 GB
      │
      ▼
LVM PHYSICAL VOLUME
      │
      ▼
VOLUME GROUP
ubuntu-vg
      │
      ▼
LOGICAL VOLUME
ubuntu-lv
98.47 GiB
      │
      ▼
FILESYSTEM
ext4
      │
      ▼
MOUNT POINT
/
      │
      ▼
DIRECTORIES / FILES
```

This distinction is critical during storage incidents.

A disk, partition, logical volume, filesystem, mount point, directory, and file are **different storage layers**.

---

# 6. LVM Investigation

LVM consists primarily of:

```text
PV
Physical Volume
      │
      ▼
VG
Volume Group
      │
      ▼
LV
Logical Volume
```

---

## Physical volumes

```bash
sudo pvs
```

Observed:

```text
PSize       ~196.95G
PFree         98.47G
```

### Purpose

Provides concise information about LVM physical volumes.

---

## Volume groups

```bash
sudo vgs
```

Observed:

```text
VG          VSize       VFree
ubuntu-vg   <196.95g    98.47g
```

Detailed information:

```bash
sudo vgdisplay
```

Important output:

```text
VG Size               <196.95 GiB
Alloc PE / Size       25209 / 98.47 GiB
Free PE / Size        25209 / 98.47 GiB
```

Therefore:

```text
ubuntu-vg
196.95 GiB
     │
     ├── Allocated: 98.47 GiB
     │
     └── Free:      98.47 GiB
```

Approximately half of the volume group remained unallocated.

---

# 7. Logical Volume Investigation

```bash
sudo lvs
```

Observed:

```text
LV          VG          LSize
ubuntu-lv   ubuntu-vg   98.47g
```

Scan logical volumes:

```bash
sudo lvscan
```

Observed:

```text
ACTIVE '/dev/ubuntu-vg/ubuntu-lv' [98.47 GiB]
```

Detailed command:

```bash
sudo lvdisplay
```

---

## LVM Command Pattern

```text
SUMMARY             DETAILED

pvs                 pvdisplay
vgs                 vgdisplay
lvs                 lvdisplay
```

---

# 8. Important Capacity Distinction

The server demonstrated two different meanings of "free storage."

### Filesystem available space

Measured with:

```bash
df -h /
```

This represents available capacity **inside the existing filesystem**.

### LVM free capacity

Measured with:

```bash
sudo vgs
```

This represents capacity in the volume group that has **not yet been assigned to a logical volume**.

Therefore:

```text
200 GB disk

does NOT automatically mean

200 GB root filesystem
```

The observed architecture was approximately:

```text
/dev/sda
200 GB
   │
   ▼
/dev/sda3
196.9 GB
   │
   ▼
ubuntu-vg
196.95 GiB
   │
   ├── ubuntu-lv: 98.47 GiB
   │
   └── VG Free:   98.47 GiB
```

---

# 9. Create Safe Incident Filesystem

Rather than filling the production root filesystem, a dedicated test filesystem was created.

Create 1 GiB image:

```bash
sudo fallocate -l 1G /opt/noc-lab/storage-lab.img
```

Create ext4 filesystem:

```bash
sudo mkfs.ext4 /opt/noc-lab/storage-lab.img
```

Create mount point:

```bash
sudo mkdir -p /mnt/noc-storage
```

Mount using a loop device:

```bash
sudo mount -o loop /opt/noc-lab/storage-lab.img /mnt/noc-storage
```

Architecture:

```text
/opt/noc-lab/storage-lab.img
          │
          ▼
      /dev/loop0
     TYPE = loop
          │
          ▼
         ext4
    FSTYPE = ext4
          │
          ▼
 /mnt/noc-storage
```

---

# 10. Verify Test Filesystem

```bash
findmnt /mnt/noc-storage
```

Identified:

```text
SOURCE: /dev/loop0
FSTYPE: ext4
TARGET: /mnt/noc-storage
```

Capacity:

```bash
df -h /mnt/noc-storage
```

Initial state:

```text
Filesystem     Size   Used   Avail   Use%
/dev/loop0     974M    24K    907M     1%
```

The image was created as 1 GiB, while the usable filesystem capacity was approximately 974 MiB due to filesystem structures/reserved space.

---

# 11. Inject Storage Incident

Create application-log directory:

```bash
sudo mkdir -p /mnt/noc-storage/app-logs
```

Generate approximately 850 MiB of test data:

```bash
sudo dd if=/dev/zero \
  of=/mnt/noc-storage/app-logs/application.log \
  bs=1M count=850 status=progress
```

Filesystem state became:

```text
/dev/loop0    974M    851M    57M    94%
```

INC-LNX-007 was now active.

---

# 12. Identify Constrained Filesystem

```bash
df -h
```

Observed:

```text
/dev/loop0    974M    851M    57M    94%    /mnt/noc-storage
```

The affected filesystem was immediately distinguishable from the healthy root filesystem.

---

# 13. `df` vs `du`

This distinction is fundamental.

```text
df
 │
 ▼
FILESYSTEM utilization
```

versus:

```text
du
 │
 ▼
DIRECTORY / FILE utilization
```

`df` answers:

> Which filesystem is full?

`du` answers:

> Where inside that filesystem is the capacity being consumed?

---

# 14. Directory-Level Investigation

Once the affected mount is identified:

```bash
sudo du -xh --max-depth=1 /mnt/noc-storage
```

Options:

```text
-x
Stay on the same filesystem.

-h
Human-readable output.

--max-depth=1
Show immediate directory-level totals.
```

Then drill down:

```bash
sudo du -ah /mnt/noc-storage/app-logs | sort -h
```

This moves the investigation from:

```text
FILESYSTEM
     │
     ▼
DIRECTORY
     │
     ▼
FILE
```

---

# 15. Large-File Discovery

An initial broad search was performed:

```bash
sudo find / -type f -size +100M
```

This found:

```text
/swap.img
/proc/kcore
/usr/lib/...
/mnt/noc-storage/app-logs/application.log
/opt/noc-lab/storage-lab.img
/var/cache/apt/...
```

It also produced transient `/proc` errors.

Example:

```text
find: '/proc/.../fdinfo/...': No such file or directory
```

This can occur because `/proc` is dynamic. Processes and file descriptors may disappear while `find` is traversing it.

---

## Better targeted search

After `df` identifies the affected filesystem:

```bash
sudo find /mnt/noc-storage -xdev -type f -size +100M -ls
```

### Purpose

Search only the affected filesystem.

`-xdev` prevents traversal onto other filesystems.

This reduces noise and makes incident investigation more efficient.

---

# 16. File Metadata Investigation

Before deleting the large file:

```bash
stat /mnt/noc-storage/app-logs/application.log
```

Observed:

```text
Size:   891289600 bytes
Owner:  root
Group:  root
Mode:   0644

Birth:  2026-08-17 19:30:00 UTC
Modify: 2026-08-17 19:30:01 UTC
Change: 2026-08-17 19:30:01 UTC
Access: 2026-08-17 19:49:41 UTC
```

---

## Timestamp Meanings

### Birth

Filesystem creation timestamp for the file/inode where supported.

### Modify — `mtime`

When file contents were last modified.

### Change — `ctime`

When inode metadata or contents last changed.

`ctime` does **not** mean creation time.

### Access — `atime`

When contents were last accessed, subject to filesystem mount behavior.

---

# 17. Historical Process Attribution Limitation

`stat` does **not** tell the administrator which historical process created a file.

It can provide:

* Owner
* Group
* Size
* Timestamps
* Permissions
* Inode information

But not:

```text
"PID 1234 created this file."
```

For historical attribution, auditing must generally be configured **before the event**, such as with Linux Audit (`auditd`).

Operational distinction:

```text
lsof / fuser
      │
      ▼
Who is using this file NOW?
```

```text
stat
      │
      ▼
What metadata exists about this file?
```

```text
auditd
      │
      ▼
What process/user performed
an operation EARLIER?
```

---

# 18. Determine Process/File Relationship

Running:

```bash
sudo fuser -v /mnt/noc-storage
```

returned `kernel`.

This did **not** identify the process that created `application.log`.

The command was checking the **mount point**, not the individual file.

Target the actual file:

```bash
sudo fuser -v /mnt/noc-storage/app-logs/application.log
```

Also:

```bash
sudo lsof /mnt/noc-storage/app-logs/application.log
```

For the original 850 MiB test file, both returned no process.

Conclusion:

```text
application.log
850 MiB
     │
     ▼
fuser
no process
     │
     ▼
lsof
no process
     │
     ▼
No running process currently
has the file open
```

The one-shot `dd` process had already exited.

---

# 19. Remediation Decision

Before removing a large production file, determine:

* Is a process currently writing to it?
* Is the file required?
* Is retention required?
* Is the file part of application state?
* Is log rotation supposed to manage it?
* Can it be archived?
* Can it safely be truncated?
* Will deleting it actually release capacity?

In this controlled incident:

* File was lab-generated data.
* No process had it open.
* No retention requirement existed.
* File was safe to remove.

Remove:

```bash
sudo rm /mnt/noc-storage/app-logs/application.log
```

---

# 20. Verify First Incident Recovery

Before:

```text
/dev/loop0    974M    851M    57M    94%
```

After:

```text
/dev/loop0    974M     28K   907M     1%
```

Recovery:

```text
94% utilized
     │
     ▼
Remove inactive test log
     │
     ▼
1% utilized
```

Approximately 850 MiB was recovered.

---

# 21. Verify Application Health

Service-level verification:

```bash
systemctl status noc-app
```

Functional verification:

```bash
sudo tail -f /var/log/noc-app.log
```

Observed timestamps continued every ten seconds.

Therefore:

```text
STORAGE REMEDIATED
       │
       ▼
Filesystem recovered
       │
       ▼
noc-app still running
       │
       ▼
Application log continues advancing
       │
       ▼
FUNCTIONALLY HEALTHY
```

---

# 22. Advanced Incident — Deleted File Still Consuming Space

A second incident reproduced a common Linux storage problem:

```text
Filesystem nearly full
       │
       ▼
Large file discovered
       │
       ▼
Administrator deletes file
       │
       ▼
ls says file is gone
       │
       ▼
du says usage is low
       │
       ▼
df STILL says filesystem is full
```

---

# 23. Create Continuous Log Generator

Create:

```bash
sudo nano /opt/noc-lab/log-generator.sh
```

Contents:

```bash
#!/bin/bash

while true
do
    dd if=/dev/zero bs=1M count=10 2>/dev/null
    sleep 1
done >> /mnt/noc-storage/app-logs/application.log
```

Make executable:

```bash
sudo chmod +x /opt/noc-lab/log-generator.sh
```

Start in background:

```bash
sudo /opt/noc-lab/log-generator.sh &
```

This continuously writes approximately 10 MiB per iteration to:

```text
/mnt/noc-storage/app-logs/application.log
```

---

# 24. Suspend the Process

The background command returned PID:

```text
11494
```

Suspend:

```bash
sudo kill -STOP 11494
```

Shell reported:

```text
Stopped sudo /opt/noc-lab/log-generator.sh
```

Verify:

```bash
ps -o pid,stat,cmd -p 11494
```

Observed:

```text
PID     STAT
11494   T
```

`T` indicates a stopped/suspended process.

---

# 25. Discover Actual Writer

Investigate:

```bash
sudo fuser -v /mnt/noc-storage/app-logs/application.log
```

Observed:

```text
PID      COMMAND
11496    log-generator.sh
11946    sleep
```

This revealed an important process hierarchy distinction.

PID `11494` was the `sudo` wrapper, while PID `11496` was the actual shell running:

```text
/opt/noc-lab/log-generator.sh
```

Process model:

```text
shell
  │
  ▼
sudo
PID 11494
  │
  ▼
log-generator.sh
PID 11496
  │
  ▼
sleep / dd
```

---

# 26. Filesystem Reaches 100%

Observed:

```text
/dev/loop0    974M    958M    0    100%
```

Directory usage:

```bash
du -sh /mnt/noc-storage/app-logs
```

At this stage, both `df` and `du` reflected high usage because the large file still had a directory entry.

---

# 27. Delete File While Process Holds It Open

The file was deleted while its inode remained referenced by an open file descriptor.

After deletion:

```bash
sudo du -sh /mnt/noc-storage
```

Result:

```text
24K
```

But:

```bash
df -h /mnt/noc-storage
```

still reported:

```text
/dev/loop0    974M    958M    0    100%
```

This produced the classic:

```text
du = 24K

BUT

df = 958M / 100%
```

---

# 28. Why `df` and `du` Disagree

Linux does not immediately release file data merely because the filename is removed if a process still has the inode open.

```text
application.log
      │
      ▼
rm application.log
      │
      ▼
Directory entry removed
      │
      ▼
ls cannot see file
      │
      ▼
du cannot walk file
      │
      BUT
      ▼
Process still holds
open file descriptor
      │
      ▼
inode remains allocated
      │
      ▼
data blocks remain allocated
      │
      ▼
df still reports usage
```

Therefore:

### `du`

Traverses accessible files/directories.

The deleted file has no directory entry, so `du` no longer counts it.

### `df`

Examines filesystem-level block allocation.

The blocks are still allocated because the inode remains open.

---

# 29. Detect Deleted-But-Open Files

Run:

```bash
sudo lsof +L1
```

### Purpose

Identifies open files whose link count is less than 1, typically files that have been deleted but remain open by a process.

The investigation showed PID:

```text
11496
```

still held the deleted application log.

Diagnostic workflow:

```text
df reports full
      │
      ▼
du reports little usage
      │
      ▼
Suspect deleted/open files
      │
      ▼
lsof +L1
      │
      ▼
PID 11496
      │
      ▼
Deleted inode still open
```

---

# 30. Process-State Investigation

Inspect:

```bash
ps -o pid,ppid,stat,cmd -p 11494,11496,11946
```

Observed:

```text
PID      PPID     STAT
11494    1463     T
11496    11495    T
```

Both relevant processes were stopped.

---

# 31. Linux Signal Behavior

A normal:

```bash
sudo kill <PID>
```

sends:

```text
SIGTERM
```

SIGTERM requests orderly termination.

A stopped process may have a termination signal pending while it is not executing normally.

Resume with:

```bash
sudo kill -CONT 11496
```

`SIGCONT` resumes a stopped process.

Immediately afterward:

```bash
sudo kill 11496
```

returned:

```text
kill: (11496): No such process
```

This indicated PID `11496` had already terminated after being resumed.

Verification:

```bash
ps -p 11496
```

returned no process.

---

# 32. Capacity Released

After PID `11496` terminated:

```bash
sudo lsof +L1
```

returned no deleted/open file for the incident.

Then:

```bash
df -h /mnt/noc-storage
```

showed:

```text
/dev/loop0    974M    28K    907M    1%
```

Full recovery sequence:

```text
BEFORE
958M used
100%
     │
     ▼
application.log deleted
     │
     ▼
du = 24K
df = 958M
     │
     ▼
lsof +L1
     │
     ▼
PID 11496 holds deleted inode
     │
     ▼
Process state = T
     │
     ▼
SIGCONT
     │
     ▼
Process resumes/terminates
     │
     ▼
Open FD closes
     │
     ▼
No links + no open FD
     │
     ▼
Kernel releases inode
and data blocks
     │
     ▼
AFTER
28K used
907M available
1%
```

---

# 33. Process Tree Investigation

Run:

```bash
ps -ef --forest | grep -A5 -B2 'log-generator'
```

Observed:

```text
sudo /opt/noc-lab/log-generator.sh
  └─ [sudo] <defunct>
```

The process tree revealed:

```text
PID 11494
sudo wrapper

PID 11495
[sudo] <defunct>
```

---

# 34. Zombie Processes

`<defunct>` represents a zombie process.

A zombie has already terminated but its parent has not yet collected its exit status.

Important:

> A zombie is not a normally running process waiting to be killed.

The executable work has already ended.

The remaining parent/process hierarchy must reap the terminated child.

---

# 35. Cleanup

The remaining lab wrapper was terminated because it was known to be safe:

```bash
sudo kill -9 11494
```

Verify:

```bash
ps -o pid,ppid,stat,cmd -p 11494,11495,11496
```

Then confirm storage:

```bash
df -h /mnt/noc-storage
```

Expected:

```text
1%
```

---

# 36. Final Application Verification

Verify service state:

```bash
systemctl status noc-app
```

Verify workload:

```bash
sudo tail -n 5 /var/log/noc-app.log
```

`noc-app` remained functionally healthy.

---

# 37. Primary Storage Troubleshooting Decision Tree

```text
STORAGE ALERT
      │
      ▼
df -h
      │
      ▼
Which filesystem is constrained?
      │
      ▼
Identify mount point
      │
      ▼
du -xh --max-depth=1 <mount>
      │
      ▼
Which directory?
      │
      ▼
Drill down with du/find
      │
      ▼
Which files?
      │
      ▼
stat <file>
      │
      ▼
lsof / fuser
      │
      ▼
Is a process using the file?
     / \
   YES  NO
    │    │
    │    └──► Assess retention /
    │         deletion safety
    │
    ▼
Identify process
    │
    ▼
Determine application impact
    │
    ▼
Choose remediation:
rotate / truncate / restart /
archive / remove / expand
    │
    ▼
df -h
    │
    ▼
Capacity recovered?
    │
    ▼
Verify application
    │
    ▼
Document RCA
    │
    ▼
CLOSE
```

---

# 38. `df` / `du` Discrepancy Decision Tree

```text
df says filesystem full
         │
         ▼
du totals significantly less
         │
         ▼
Possible deleted-but-open file
         │
         ▼
sudo lsof +L1
         │
      ┌──┴──┐
      │     │
   FOUND   NONE
      │     │
      ▼     ▼
Identify   Continue storage
PID        investigation
      │
      ▼
Inspect process
      │
      ▼
Determine safe remediation
      │
      ▼
Stop/restart responsible process
      │
      ▼
File descriptor closes
      │
      ▼
Kernel releases blocks
      │
      ▼
df -h
      │
      ▼
VERIFY RECOVERY
```

---

# 39. Command Reference

| Command                                     | Purpose                                                        |
| ------------------------------------------- | -------------------------------------------------------------- |
| `findmnt`                                   | Display mounted filesystem hierarchy                           |
| `findmnt <mount>`                           | Inspect a specific mount                                       |
| `df -h`                                     | Display filesystem capacity/utilization                        |
| `df -h <mount>`                             | Inspect capacity of a specific filesystem                      |
| `du -sh <path>`                             | Summarize directory/file disk usage                            |
| `du -xh --max-depth=1 <path>`               | Find immediate directory usage while staying on one filesystem |
| `du -ah <path>`                             | Display usage for directories and files                        |
| `sort -h`                                   | Sort human-readable sizes                                      |
| `lsblk`                                     | Display block-device hierarchy                                 |
| `pvs`                                       | Summarize LVM physical volumes                                 |
| `pvdisplay`                                 | Detailed physical-volume information                           |
| `vgs`                                       | Summarize volume groups                                        |
| `vgdisplay`                                 | Detailed volume-group information                              |
| `lvs`                                       | Summarize logical volumes                                      |
| `lvdisplay`                                 | Detailed logical-volume information                            |
| `lvscan`                                    | Scan and report logical-volume state                           |
| `find <path> -xdev -type f -size +100M -ls` | Find large files on one filesystem                             |
| `stat <file>`                               | Display file metadata and timestamps                           |
| `fuser -v <file>`                           | Identify processes currently using a file                      |
| `lsof <file>`                               | Show processes with a file open                                |
| `lsof -p <PID>`                             | Show files/resources opened by a PID                           |
| `lsof +L1`                                  | Find deleted files still held open                             |
| `ps -fp <PID>`                              | Display detailed process information                           |
| `ps -o pid,ppid,stat,cmd -p <PID>`          | Inspect PID, parent, state, and command                        |
| `ps -ef --forest`                           | Display process hierarchy                                      |
| `kill <PID>`                                | Send SIGTERM                                                   |
| `kill -STOP <PID>`                          | Suspend process execution                                      |
| `kill -CONT <PID>`                          | Resume stopped process                                         |
| `kill -9 <PID>`                             | Send SIGKILL                                                   |
| `fallocate -l 1G <file>`                    | Allocate a file of specified size                              |
| `mkfs.ext4 <device/file>`                   | Create ext4 filesystem                                         |
| `mount -o loop <image> <mount>`             | Mount filesystem image through loop device                     |
| `dd`                                        | Copy/generate block-oriented data                              |
| `systemctl status noc-app`                  | Verify service state                                           |
| `tail -f /var/log/noc-app.log`              | Verify actual application activity                             |

---

# 40. Key Operational Lessons

1. **Start storage incidents with the filesystem, not random directories.**

```text
df → mount → du → file
```

2. A 200 GB disk does not necessarily mean `/` has a 200 GB filesystem.

3. Understand the complete storage stack:

```text
Disk
 ↓
Partition
 ↓
PV
 ↓
VG
 ↓
LV
 ↓
Filesystem
 ↓
Mount
 ↓
Directory
 ↓
File
```

4. `df` and `du` measure different things.

5. Once the affected filesystem is known, scope `find` and `du` to that filesystem.

6. Do not automatically delete the largest file.

7. Determine whether a process has the file open first.

8. `fuser` and `lsof` identify **current** file/process relationships.

9. `stat` provides filesystem metadata but does not identify the historical process that created a file.

10. Historical attribution requires auditing/telemetry established before the event.

11. Deleting a file does not necessarily release its blocks immediately.

12. A deleted file remains allocated while a process maintains an open file descriptor to it.

13. A large discrepancy between `df` and `du` should raise suspicion of deleted-but-open files.

14. Use:

```bash
sudo lsof +L1
```

to investigate deleted files that remain open.

15. `STAT=T` means a process is stopped.

16. `SIGSTOP` suspends a process.

17. `SIGCONT` resumes a stopped process.

18. `SIGTERM` requests orderly termination.

19. `SIGKILL` forces kernel-level termination and should be used deliberately.

20. `<defunct>` indicates a zombie process that has already terminated.

21. Never declare a storage incident resolved merely because a file was deleted.

22. Verify capacity afterward:

```bash
df -h
```

23. Verify the dependent application at both the service and functional levels.

---

# 41. Incident Closure — INC-LNX-007

## Incident 1 — Filesystem Capacity

**Symptom:**
Filesystem exceeded critical utilization threshold.

**Affected filesystem:**

```text
/dev/loop0
```

**Mount:**

```text
/mnt/noc-storage
```

**Peak utilization:**

```text
94%
```

**Capacity consumer:**

```text
/mnt/noc-storage/app-logs/application.log
```

**Size:**

```text
~850 MiB
```

**Process relationship:**
No running process had the file open.

**Root cause:**
Large inactive application-log/test file consumed the majority of available filesystem capacity.

**Remediation:**
Removed file after verifying it was safe to delete.

**Recovery:**

```text
94% → 1%
```

**Application verification:**
`noc-app` remained active and continued generating expected log entries every ten seconds.

**Status:** `RESOLVED`

---

# 42. Advanced Incident Closure — Deleted/Open File

**Symptom:**
Filesystem remained 100% utilized after large log file was deleted.

**Evidence:**

```text
du = 24K
df = 958M / 100%
```

**Diagnostic command:**

```bash
sudo lsof +L1
```

**Responsible process:**

```text
PID 11496
log-generator.sh
```

**Process state:**

```text
T — stopped
```

**Root cause:**
The log's directory entry had been removed, but the running/stopped process retained an open file descriptor to the deleted inode. The filesystem therefore could not release its allocated blocks.

**Remediation:**
Process was resumed/terminated, releasing the open file descriptor.

**Recovery:**

```text
100% → 1%
958M → 28K used
907M available
```

**Application verification:**
`noc-app` remained operational and functionally healthy.

**Status:** `RESOLVED`

---

# 43. Skills Demonstrated

* Linux storage administration
* Filesystem monitoring
* Block-device identification
* Mount analysis
* LVM PV/VG/LV analysis
* Filesystem-capacity triage
* Disk-usage investigation
* Large-file discovery
* File metadata analysis
* Process/file correlation
* File-descriptor investigation
* Inode behavior
* Deleted-file troubleshooting
* `df` versus `du`
* Linux signals
* Process states
* Process-tree analysis
* Zombie-process recognition
* Safe remediation
* Post-change validation
* Application-health verification
* L2 incident ownership
* Root-cause analysis

---

# 44. Lab Status

**Lab:** Linux Administration Lab #007
**Topic:** Disk Capacity, Filesystem & LVM Incident Troubleshooting
**Host:** `devops02`
**Incident:** `INC-LNX-007`
**Status:** **COMPLETE / RESOLVED**

---

# 45. Next Lab

**RB-0008 — Package Management, Patching & Repository Troubleshooting**

Planned topics:

* `apt`
* Package inventory
* Repository configuration
* Package updates
* Security updates
* Dependency failures
* Held packages
* Failed installations
* Service impact
* Pre/post-patch verification
* Change-control workflow
* Package troubleshooting
* Rollback-minded remediation

```

