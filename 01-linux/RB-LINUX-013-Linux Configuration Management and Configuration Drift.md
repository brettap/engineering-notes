# RB-013 — Linux Configuration Management and Configuration Drift

**Category:** Linux System Administration
**Environment:** Techworks Lab
**Target Host:** `devops02`
**Difficulty:** Intermediate
**Status:** Completed — Manual Configuration Management Phase
**Primary Concepts:** Configuration baselines, configuration drift, Linux groups, directory ownership, permissions, setgid, validation, rollback

---

## 1. Objective

Establish and validate a defined configuration baseline on a Linux server.

This runbook demonstrates how to:

* Define a desired configuration state.
* Audit the current state.
* Identify configuration drift.
* Separate discovery from remediation.
* Implement an approved configuration change.
* Validate the resulting configuration.
* Functionally test permissions.
* Recover from a change performed on the wrong host.
* Document configuration-management evidence.

The lab intentionally uses manual configuration management before introducing automation such as Ansible.

---

# 2. Configuration Management Concept

Configuration management compares the **desired state** of a system with its **current state**.

```text
              CONFIGURATION MANAGEMENT

                   Desired State
                "What should exist?"
                         │
                         │ compare
                         ▼
                  Current State
                "What exists now?"
                         │
                  Configuration
                    different?
                    /       \
                  NO         YES
                  │           │
                  ▼           ▼
              COMPLIANT     DRIFT
                              │
                              ▼
                         REMEDIATION
                              │
                              ▼
                         VERIFICATION
```

A server can be operational while still being incorrectly configured.

```text
Monitoring:
"Is the system working?"

Configuration Management:
"Is the system configured correctly?"
```

Both are required for reliable infrastructure operations.

---

# 3. Scenario

A routine configuration review indicated that `devops02` might no longer match the approved Linux application-server baseline.

The administrator was tasked with:

1. Determining the current configuration.
2. Comparing the current state with the approved baseline.
3. Identifying configuration drift.
4. Recording discrepancies before changing anything.
5. Developing a remediation plan.
6. Implementing the changes.
7. Validating the resulting configuration.
8. Providing evidence that the system reached the desired state.

Operational workflow:

```text
OBSERVE
   │
   ▼
COMPARE
   │
   ▼
IDENTIFY DRIFT
   │
   ▼
PROPOSE CHANGE
   │
   ▼
IMPLEMENT
   │
   ▼
VERIFY
   │
   ▼
FUNCTIONALLY TEST
   │
   ▼
DOCUMENT
```

---

# 4. Approved Configuration Baseline

| Configuration Item     | Required State              |
| ---------------------- | --------------------------- |
| Hostname               | `devops02`                  |
| SSH                    | Installed, enabled, running |
| Time synchronization   | Enabled and synchronized    |
| `curl`                 | Installed                   |
| `vim`                  | Installed                   |
| `git`                  | Installed                   |
| `htop`                 | Installed                   |
| `techops` group        | Exists                      |
| `brettcoder`           | Member of `techops`         |
| `/opt/techworks`       | Exists                      |
| `/opt/techworks` owner | `root`                      |
| `/opt/techworks` group | `techops`                   |
| `/opt/techworks` mode  | `2775`                      |
| Root filesystem        | Below 80% utilization       |
| Failed systemd units   | None                        |

---

# 5. Pre-Change Target Verification

Before performing configuration changes, verify the target system.

```bash
hostname
```

Expected:

```text
devops02
```

This became an explicit control during the lab after configuration changes were accidentally made on `ubuntu-devops01`.

## Operational Lesson

Never assume the active terminal belongs to the intended server.

This is particularly important when multiple SSH sessions are open.

```text
CHANGE REQUEST
      │
      ▼
hostname
      │
      ▼
Correct host?
   /       \
 NO         YES
 │           │
STOP       CONTINUE
```

`hostname` should therefore be treated as a **pre-change control**, not merely a basic Linux information command.

---

# 6. Baseline Audit

## 6.1 Hostname

```bash
hostname
```

Result:

```text
devops02
```

**Status:** PASS

---

## 6.2 SSH Service

```bash
systemctl status ssh
```

Relevant output:

```text
Loaded: loaded (...; enabled; preset: enabled)
Active: active (running)
```

This establishes that SSH is:

* Installed
* Enabled
* Running

**Status:** PASS

---

# 7. Time Synchronization

Initial inspection with:

```bash
date
```

only established the displayed system time.

It did **not** prove synchronization.

The correct configuration-management check was:

```bash
timedatectl
```

Relevant output:

```text
System clock synchronized: yes
NTP service: active
RTC in local TZ: no
```

**Status:** PASS

## Lesson

```text
Clock displays correct-looking time
              ≠
Clock synchronization confirmed
```

Configuration audits should verify the actual requirement rather than infer compliance from related information.

---

# 8. Package/Application Audit

## curl

```bash
curl --version
```

Result:

```text
curl 8.5.0
```

**Status:** PASS

---

## vim

```bash
vim --version
```

Result included:

```text
VIM - Vi IMproved 9.1
```

**Status:** PASS

---

## git

```bash
git --version
```

Result:

```text
git version 2.43.0
```

**Status:** PASS

---

## htop

```bash
htop --version
```

Result:

```text
htop 3.3.0
```

**Status:** PASS

---

# 9. Group Configuration Audit

Required group:

```text
techops
```

The system initially contained a similarly named group:

```bash
getent group techworks
```

Result:

```text
techworks:x:1001:
```

However, `techworks` does not satisfy a baseline requiring `techops`.

```text
"It looks reasonable"
        ≠
"It matches the approved configuration"
```

**Status:** DRIFT

### Drift Finding #1

```text
Required group "techops" does not exist.
```

---

# 10. User Group Membership Audit

Group membership was checked with:

```bash
id -nG brettcoder
```

Initial result:

```text
brettcoder adm cdrom sudo dip plugdev lxd
```

`techops` was absent.

**Status:** DRIFT

### Drift Finding #2

```text
User "brettcoder" is not a member of required group "techops".
```

---

# 11. Understanding `/etc/passwd`

The following command was also used during investigation:

```bash
cat /etc/passwd | grep "brettcoder"
```

Result:

```text
brettcoder:x:1000:1000:techworks:/home/brettcoder:/bin/bash
```

This must **not** be interpreted as proof that `brettcoder` belongs to the `techworks` group.

The `/etc/passwd` fields are:

```text
brettcoder:x:1000:1000:techworks:/home/brettcoder:/bin/bash
    │      │   │    │      │            │             │
    │      │   │    │      │            │             └── shell
    │      │   │    │      │            └── home
    │      │   │    │      └── GECOS/comment
    │      │   │    └── primary GID
    │      │   └── UID
    │      └── password placeholder
    └── username
```

The word `techworks` in this entry is the **GECOS/comment field**, not group membership.

Preferred membership checks include:

```bash
id -nG brettcoder
```

```bash
groups brettcoder
```

and for a specific group:

```bash
getent group techops
```

---

# 12. Application Directory Audit

Required directory:

```text
/opt/techworks
```

The directory did not initially exist.

**Status:** DRIFT

### Drift Finding #3

```text
Required directory /opt/techworks does not exist.
```

Because the directory was absent, the following requirements could not yet be satisfied:

```text
owner = root
group = techops
mode  = 2775
```

These were treated as dependent requirements rather than separate root-cause drift findings.

---

# 13. Root Filesystem Audit

The root filesystem was checked specifically:

```bash
df -h /
```

Result:

```text
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   48G   20G   26G  43% /
```

Required:

```text
< 80%
```

Actual:

```text
43%
```

**Status:** PASS

## Lesson

When the requirement concerns `/`, querying only the relevant filesystem is preferable to generating unnecessary output for every mounted filesystem.

---

# 14. Failed systemd Unit Audit

Two valid methods were identified.

```bash
systemctl --failed
```

or:

```bash
systemctl list-units --state=failed
```

Result:

```text
0 loaded units listed.
```

**Status:** PASS

---

# 15. Pre-Remediation Assessment

| Configuration         | Desired             | Initial State       | Result    |
| --------------------- | ------------------- | ------------------- | --------- |
| Hostname              | `devops02`          | `devops02`          | PASS      |
| SSH                   | Enabled/running     | Enabled/running     | PASS      |
| Time synchronization  | Active/synchronized | Active/synchronized | PASS      |
| curl                  | Installed           | Installed           | PASS      |
| vim                   | Installed           | Installed           | PASS      |
| git                   | Installed           | Installed           | PASS      |
| htop                  | Installed           | Installed           | PASS      |
| Group                 | `techops`           | Absent              | DRIFT     |
| brettcoder membership | `techops`           | Absent              | DRIFT     |
| `/opt/techworks`      | Exists              | Absent              | DRIFT     |
| Directory owner       | `root`              | N/A                 | DEPENDENT |
| Directory group       | `techops`           | N/A                 | DEPENDENT |
| Directory mode        | `2775`              | N/A                 | DEPENDENT |
| Root utilization      | <80%                | 43%                 | PASS      |
| Failed systemd units  | 0                   | 0                   | PASS      |

---

# 16. Configuration Remediation

## Create the Operations Group

```bash
sudo groupadd techops
```

Verify:

```bash
getent group techops
```

---

## Add `brettcoder` to `techops`

```bash
sudo usermod -aG techops brettcoder
```

The `-G` option specifies supplementary groups.

The `-a` option means **append**.

This distinction is important.

Correct:

```bash
sudo usermod -aG techops brettcoder
```

Potentially dangerous:

```bash
sudo usermod -G techops brettcoder
```

Without `-a`, existing supplementary group assignments can be replaced.

---

# 17. Create the Application Directory

Create:

```bash
sudo mkdir /opt/techworks
```

Set ownership:

```bash
sudo chown root:techops /opt/techworks
```

Set permissions:

```bash
sudo chmod 2775 /opt/techworks
```

Desired result:

```text
drwxrwsr-x root techops ... /opt/techworks
```

---

# 18. Understanding `chown` vs `chgrp`

An unsuccessful command attempted during the lab was:

```bash
sudo chown techops /opt/techworks
```

This does **not** mean:

```text
change group ownership to techops
```

It means:

```text
change USER ownership to user "techops"
```

Because `techops` is a group rather than a user, this was incorrect.

## Change only the group

```bash
sudo chgrp techops /opt/techworks
```

## Change user owner and group owner together

```bash
sudo chown root:techops /opt/techworks
```

For this baseline, the latter explicitly establishes the complete desired ownership state.

---

# 19. Understanding Mode `2775`

Normal mode:

```text
775
```

means:

```text
OWNER     GROUP     OTHERS
 rwx       rwx       r-x
  7         7         5
```

The additional leading `2`:

```text
2775
│└──┘
│ 775
│
└── setgid
```

sets the **setgid bit**.

For a shared directory, this causes newly created files and subdirectories to inherit the directory's group ownership.

Desired architecture:

```text
                 /opt/techworks
                 root:techops
                    2775
                      │
              ┌───────┴────────┐
              │                │
          brettcoder       future-admin
              │                │
              └───────┬────────┘
                      │
                 members of
                   techops
                      │
                      ▼
              shared application
                   workspace
```

This provides group-based administrative access rather than making a single administrator personally own the application directory.

---

# 20. Session-Based Group Membership Issue

After `brettcoder` was added to `techops`, access did not immediately behave as expected.

The configuration showed:

```bash
getent group techops
```

that the membership existed.

However, the existing login session had been established before the group membership change.

A logout and new login session were required before the updated supplementary group membership became effective for the user's session.

Troubleshooting pattern:

```text
Access fails
    │
    ▼
Check permissions
    │
    ▼
Permissions correct
    │
    ▼
Check group membership
    │
    ▼
Membership recently changed?
    │
    ▼
   YES
    │
    ▼
Start new login session
    │
    ▼
Check effective groups
    │
    ▼
Retest access
```

Verify with:

```bash
id -nG brettcoder
```

Post-change result:

```text
brettcoder adm cdrom sudo dip plugdev lxd techops
```

**Status:** PASS

---

# 21. Post-Change Directory Validation

The final directory listing showed:

```text
drwxrwsr-x 2 root techops ... techworks
```

This establishes:

```text
/opt/techworks
│
├── user owner: root       PASS
├── group owner: techops   PASS
├── owner permissions: rwx
├── group permissions: rwx
├── others permissions: r-x
└── setgid: enabled        PASS
```

The mode corresponds to:

```text
2775
```

---

# 22. Functional Validation

Configuration inspection alone does not prove that the intended access model actually works.

The functional requirement was:

> `brettcoder`, as a member of `techops`, must be able to create content inside `/opt/techworks` without using sudo.

A temporary file was created as `brettcoder`.

The file inherited:

```text
user owner  = brettcoder
group owner = techops
```

The temporary test object was subsequently removed.

This confirmed both:

* Group write access works.
* The setgid inheritance behavior works.

```text
CONFIGURATION VERIFICATION

ls shows root:techops
and mode 2775
        │
        ▼
        PASS

             +

FUNCTIONAL VALIDATION

brettcoder writes without sudo
        │
        ▼
new object inherits techops
        │
        ▼
        PASS
```

---

# 23. Incident During Change — Wrong Host

During remediation, the administrator had multiple terminal sessions open.

The initial changes were accidentally performed on:

```text
ubuntu-devops01
```

instead of:

```text
devops02
```

The following unintended configuration was created:

```text
ubuntu-devops01
│
├── techops
│    └── brettcoder
│
└── /opt/techworks
```

The mistake was identified from the shell prompt and subsequently confirmed with:

```bash
hostname
```

Result:

```text
ubuntu-devops01
```

Rather than immediately deleting configuration, the system was inspected first.

---

# 24. Wrong-Host Rollback

## Verify unintended directory

```bash
ls -la /opt/techworks
```

Result:

```text
total 8
drwxrwsr-x 2 root root ... .
drwxr-xr-x 4 root root ... ..
```

The directory was empty.

## Verify unintended group

```bash
getent group techops
```

Result:

```text
techops:x:1001:brettcoder
```

With the unintended configuration confirmed, rollback was performed.

---

## Remove Empty Directory

```bash
sudo rmdir /opt/techworks
```

`rmdir` was preferred over:

```bash
rm -rf
```

because `rmdir` refuses to delete a non-empty directory.

This provides an additional safety control.

Verification:

```bash
ls -ld /opt/techworks
```

Result:

```text
ls: cannot access '/opt/techworks': No such file or directory
```

---

## Remove Unintended Group

```bash
sudo groupdel techops
```

Verify:

```bash
getent group techops
```

No result confirmed removal.

User membership was then checked:

```bash
id -nG brettcoder
```

Result:

```text
brettcoder adm cdrom sudo dip plugdev lxd docker
```

The unintended configuration on `ubuntu-devops01` was successfully removed.

---

# 25. Wrong-Host Incident Lesson

The incident produced an important operational control:

```text
BEFORE CHANGE
     │
     ▼
hostname
     │
     ▼
VERIFY TARGET
     │
     ▼
INSPECT CURRENT STATE
     │
     ▼
APPLY CHANGE
     │
     ▼
VERIFY DESIRED STATE
```

When administering multiple systems simultaneously, terminal context must never be assumed.

A technically correct command executed against the wrong server is still an incorrect change.

---

# 26. Final Configuration State

```text
                         devops02
                            │
          ┌─────────────────┴────────────────┐
          │                                  │
          ▼                                  ▼
       techops                         /opt/techworks
          │                                  │
          │                                  ├── owner: root
          │                                  ├── group: techops
          │                                  └── mode: 2775
          │
          ▼
      brettcoder
          │
          └──────── authorized access ───────►
```

Final compliance:

| Requirement                 | Result |
| --------------------------- | ------ |
| Correct target host         | PASS   |
| Hostname                    | PASS   |
| SSH                         | PASS   |
| NTP/time synchronization    | PASS   |
| Required utilities          | PASS   |
| `techops` exists            | PASS   |
| `brettcoder` in `techops`   | PASS   |
| `/opt/techworks` exists     | PASS   |
| Owner `root`                | PASS   |
| Group `techops`             | PASS   |
| Mode `2775`                 | PASS   |
| Functional group write      | PASS   |
| setgid inheritance          | PASS   |
| Root filesystem utilization | PASS   |
| Failed systemd units        | PASS   |

**Final Status: COMPLIANT**

---

# 27. Key Lessons Learned

### Configuration state must be explicitly defined

Without a baseline, there is no objective way to determine whether a system has drifted.

### Similar is not compliant

`techworks` and `techops` are different configuration objects.

### Discovery should precede remediation

Determine the current state before modifying it.

### Verify the target before every change

```bash
hostname
```

became an important pre-change control after the wrong-host incident.

### Group-based authorization scales better than individual ownership

Using:

```text
root:techops
```

allows administrative control to remain with root while operational users receive appropriate group access.

### `-aG` matters

```bash
usermod -aG
```

preserves existing supplementary group memberships while adding another.

### Existing sessions can retain old security context

A newly assigned supplementary group may require a new login session before the effective process credentials reflect the change.

### Permissions must be functionally tested

Seeing:

```text
drwxrwsr-x
```

is configuration evidence.

Successfully writing without `sudo` and observing `techops` inheritance is functional evidence.

### Rollback should also begin with inspection

Even when a mistake is known, verify what exists before deleting or reversing anything.

---

# 28. Command Reference

## Host Identification

```bash
hostname
```

Displays the current system hostname.

Operational use: verify the target server before performing changes.

---

## Create a Linux Group

```bash
sudo groupadd <group_name>
```

Example:

```bash
sudo groupadd techops
```

Creates a new Linux group.

---

## Query a Group

```bash
getent group <group_name>
```

Example:

```bash
getent group techops
```

Confirms that a group exists and displays its group database entry.

---

## Add User to Supplementary Group

```bash
sudo usermod -aG <group_name> <username>
```

Example:

```bash
sudo usermod -aG techops brettcoder
```

Adds a user to a supplementary group while preserving existing supplementary memberships.

---

## Display User Group Membership

```bash
id -nG <username>
```

Example:

```bash
id -nG brettcoder
```

Displays the user's groups by name.

Alternative:

```bash
groups brettcoder
```

---

## Inspect `/etc/passwd`

```bash
grep "brettcoder" /etc/passwd
```

or:

```bash
cat /etc/passwd | grep "brettcoder"
```

Displays the matching account database entry.

Do not use the GECOS/comment field as evidence of group membership.

---

## Create Directory

```bash
sudo mkdir /path/to/directory
```

Example:

```bash
sudo mkdir /opt/techworks
```

Creates a directory.

---

## Inspect Directory Metadata

```bash
ls -ld /path/to/directory
```

Example:

```bash
ls -ld /opt/techworks
```

Displays permissions, user ownership, and group ownership for the directory itself.

---

## Inspect Directory Contents

```bash
ls -la /path/to/directory
```

Displays directory contents, including hidden entries.

Useful before deletion to verify whether a directory is actually empty.

---

## Change User Owner

```bash
sudo chown <username> /path/to/directory
```

Changes the user owner.

---

## Change Group Owner

```bash
sudo chgrp <group_name> /path/to/directory
```

Example:

```bash
sudo chgrp techops /opt/techworks
```

Changes group ownership without changing the user owner.

---

## Recursively Change Group Ownership

```bash
sudo chgrp -R <group_name> /path/to/directory
```

Applies group ownership recursively through a directory tree.

Use recursive operations carefully.

---

## Change User and Group Ownership Together

```bash
sudo chown <user>:<group> /path/to/directory
```

Example:

```bash
sudo chown root:techops /opt/techworks
```

Explicitly sets both user and group ownership.

---

## Set Directory Permissions and setgid

```bash
sudo chmod 2775 /path/to/directory
```

Example:

```bash
sudo chmod 2775 /opt/techworks
```

Provides:

```text
owner  = rwx
group  = rwx
others = r-x
setgid = enabled
```

Expected symbolic representation:

```text
drwxrwsr-x
```

---

## Remove Empty Directory

```bash
sudo rmdir /path/to/directory
```

Removes an empty directory.

Safer than recursive deletion when the directory is expected to be empty because it fails if content exists.

---

## Delete Group

```bash
sudo groupdel <group_name>
```

Example:

```bash
sudo groupdel techops
```

Deletes a Linux group.

---

## Check Root Filesystem Utilization

```bash
df -h /
```

Displays human-readable capacity and utilization for the filesystem containing `/`.

---

## Check Time Synchronization

```bash
timedatectl
```

Displays:

* Local time
* UTC
* RTC
* Timezone
* NTP state
* System clock synchronization

Important fields:

```text
System clock synchronized: yes
NTP service: active
```

---

## Check SSH

```bash
systemctl status ssh
```

Displays SSH service state and whether the service is enabled.

---

## Check Failed systemd Units

```bash
systemctl --failed
```

Alternative:

```bash
systemctl list-units --state=failed
```

Displays systemd units currently in a failed state.

---

## Verify Installed Utilities

```bash
curl --version
vim --version
git --version
htop --version
```

Confirms that each executable exists and reports its installed version.

---

# 29. Configuration Management Progression

RB-013 establishes the manual foundation for configuration management.

```text
MANUAL BASELINE
      │
      ▼
MANUAL AUDIT
      │
      ▼
CONFIGURATION DRIFT
      │
      ▼
REMEDIATION
      │
      ▼
POST-CHANGE VERIFICATION
      │
      ▼
FUNCTIONAL VALIDATION
      │
      ▼
AUTOMATED COMPLIANCE CHECK
      │
      ▼
IDEMPOTENCY
      │
      ▼
ANSIBLE
      │
      ▼
CENTRALIZED DESIRED STATE
ACROSS MULTIPLE SERVERS
```

The administrative problem becomes increasingly obvious as server count grows.

Manually checking one server is manageable.

Manually checking 50 servers is inefficient and error-prone.

Configuration-management automation exists to make the desired state **repeatable, testable, scalable, and auditable**.

---

# 30. Runbook Completion

**RB-013 Manual Phase: COMPLETE**

Skills demonstrated:

* Linux configuration auditing
* Baseline comparison
* Configuration-drift identification
* Linux group administration
* Supplementary group management
* Linux directory ownership
* Linux permissions
* setgid shared-directory behavior
* systemd health validation
* filesystem capacity verification
* NTP/time synchronization verification
* pre-change target validation
* post-change validation
* functional permissions testing
* rollback of an unintended configuration change
* operational evidence collection

**Next phase:** Automated configuration-compliance checking, idempotency, and Ansible.
