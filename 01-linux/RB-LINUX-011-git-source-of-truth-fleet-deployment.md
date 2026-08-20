Yes. RB-LINUX-011 is complete. This version incorporates the **actual work performed**, including the canary deployment, SHA-256 verification, email reporting, kernel update/reboot cycle, fleet rollout, and the transition point to Ansible.

Save it as:

```text
RB-LINUX-011-git-source-of-truth-fleet-deployment.md
```

# RB-LINUX-011 — Git Source of Truth and Linux Fleet Deployment

## Purpose

Establish Git as the authoritative source for Linux management scripts and implement a controlled process for validating, deploying, testing, and verifying a common management artifact across multiple Linux servers.

This lab progressed from manual Linux administration into the foundations of:

* Source control
* Artifact management
* Change control
* Canary deployments
* Configuration drift detection
* Fleet management
* Automated email reporting
* CI/CD
* Configuration management
* Ansible

---

## Environment

### Linux Fleet

```text
ubuntu-devops01
├── Git management host
├── Monitoring host
└── Managed Linux server

devops02
└── Managed Linux server

locator01
└── Managed Linux server
```

### Git Repository

```text
~/dev/projects/engineering-notes/
```

### Authoritative Management Script

```text
01-linux/Management-scripts/sys-update.sh
```

### Runtime Location

```text
/usr/local/bin/sys-update.sh
```

### Update Log

```text
/var/log/server-autoupdate.log
```

### Management Notification Flow

```text
Linux server
     │
     ▼
   msmtp
     │
     ▼
Gmail SMTP relay
     │
     ▼
support@4techworks.com
     │
     ▼
Management phone notification
```

SMTP credentials are maintained separately in:

```text
/etc/msmtprc
```

Credentials are **not stored in Git**.

---

# 1. Establish the Git Source of Truth

The original tested update script existed on `locator01`:

```text
/usr/local/bin/sys-update.sh
```

The script was located using:

```bash
sudo find / -name "sys-update.sh" 2>/dev/null
```

The current filesystem location was verified with:

```bash
pwd
```

The tested artifact was then transferred from `locator01` to the Git management host using SCP:

```bash
scp brettcoder@192.168.1.144:/usr/local/bin/sys-update.sh \
/home/brettcoder/dev/projects/engineering-notes/01-linux/Management-scripts
```

Result:

```text
engineering-notes/
└── 01-linux/
    └── Management-scripts/
        └── sys-update.sh
```

---

# 2. Verify Artifact Integrity

The source artifact was hashed on `locator01`:

```bash
sha256sum /usr/local/bin/sys-update.sh
```

The transferred Git copy was hashed on `ubuntu-devops01`:

```bash
sha256sum \
~/dev/projects/engineering-notes/01-linux/Management-scripts/sys-update.sh
```

The SHA-256 values matched.

Therefore:

```text
SOURCE ARTIFACT
      │
      ▼
   SHA-256
      │
      │ MATCH
      ▼
GIT ARTIFACT
```

This confirmed that SCP had produced a byte-for-byte identical copy.

---

# 3. Inspect Script for Secrets

Before placing the artifact under source control, the script was manually inspected.

No:

* Passwords
* SMTP App Passwords
* API keys
* Tokens
* SSH keys
* Other credentials

were present.

Secrets remained outside the repository:

```text
CODE
 │
 ├── sys-update.sh ─────────► Git
 │
SECRETS
 │
 └── /etc/msmtprc ──────────► Local protected configuration
```

---

# 4. Observe Git's Untracked State

The newly copied artifact initially appeared as:

```text
Untracked files
```

An important behavior was observed while navigating through the repository.

From:

```text
engineering-notes/
```

Git could display:

```text
01-linux/Management-scripts/sys-update.sh
```

From:

```text
engineering-notes/01-linux/
```

Git could display:

```text
Management-scripts/
```

From:

```text
engineering-notes/01-linux/Management-scripts/
```

Git displayed:

```text
./
```

The filesystem object did not move.

The administrator's **point of reference changed**.

---

# 5. Identify Git Repository Root

The repository root can be determined from anywhere inside the working tree:

```bash
git rev-parse --show-toplevel
```

Concept:

```text
engineering-notes/            ← Git repository root
│
├── 01-linux/
│   │
│   └── Management-scripts/
│       └── sys-update.sh
│
└── other repository content
```

---

# 6. Understand Git File States

The management script moved through several Git states.

Initially:

```text
UNTRACKED
```

After:

```bash
git add 01-linux/Management-scripts/sys-update.sh
```

it became:

```text
STAGED
```

Lifecycle:

```text
WORKING DIRECTORY
       │
       │ git add
       ▼
STAGING AREA
       │
       │ git commit
       ▼
LOCAL REPOSITORY
       │
       │ git push
       ▼
REMOTE REPOSITORY
```

`git add` does **not** create a commit.

It selects the version of the artifact intended for the next commit.

---

# 7. Review Staged Content

Staged changes were inspected with:

```bash
git diff --staged
```

Equivalent:

```bash
git diff --cached
```

Because `sys-update.sh` was new, Git displayed essentially the entire file.

This differs from:

```bash
cat sys-update.sh
```

`cat` answers:

> What does the current filesystem object contain?

`git diff --staged` answers:

> What changes are about to enter the next Git commit?

---

# 8. Validate Bash Syntax

The script was checked without executing it:

```bash
bash -n 01-linux/Management-scripts/sys-update.sh
```

Exit status was checked:

```bash
echo $?
```

Result:

```text
0
```

Meaning:

> Bash successfully parsed the script without detecting syntax errors.

This does **not** prove that the script functions correctly.

Validation levels:

```text
SYNTAX VALIDATION
bash -n
     │
     ▼
Can Bash parse it?
     │
     ▼
RUNTIME VALIDATION
     │
     ▼
Can it execute?
     │
     ▼
FUNCTIONAL VALIDATION
     │
     ▼
Does it produce the intended operational result?
```

---

# 9. Establish Source-of-Truth Policy

The following policy was established:

> The canonical `sys-update.sh` lives in Git. Copies under `/usr/local/bin/` are deployed runtime artifacts.

Therefore:

```text
Git:
01-linux/Management-scripts/sys-update.sh
                 │
                 ▼
       AUTHORITATIVE SOURCE

Servers:
/usr/local/bin/sys-update.sh
                 │
                 ▼
         DEPLOYED ARTIFACT
```

Directly editing individual server copies should normally be avoided.

Instead:

```text
Need change
    │
    ▼
Edit Git copy
    │
    ▼
Validate
    │
    ▼
Test
    │
    ▼
Commit
    │
    ▼
Deploy
```

---

# 10. Configuration Drift

If Git contains:

```text
SHA256 = ABC123
```

while a managed server contains:

```text
SHA256 = DEF456
```

then:

```text
DESIRED STATE != ACTUAL STATE
```

This represents:

```text
CONFIGURATION DRIFT
```

Possible causes include:

* Manual edits
* Failed deployment
* Old versions
* Unauthorized changes
* Emergency changes not returned to source control

SHA-256 therefore became useful for both:

```text
File-transfer integrity
           +
Configuration-drift detection
```

---

# 11. Initial devops02 Deployment

The script was first deployed to `devops02`.

An initial attempt was made using:

```text
git clone
```

against a GitHub raw-file URL.

This failed because `git clone` expects a **Git repository**, not an individual raw artifact.

A subsequent direct download using `wget` succeeded.

This demonstrated:

```text
git clone
    │
    └── repository operation

wget
    │
    └── individual HTTP/HTTPS resource retrieval
```

This method worked but was not selected as the final fleet-management architecture.

---

# 12. Email Infrastructure

`msmtp` was configured independently on:

```text
locator01
devops01
devops02
```

Outbound SMTP tests were performed.

All three successfully delivered messages to:

```text
support@4techworks.com
```

Notification architecture:

```text
locator01 ──┐
            │
devops01 ───┼──► Gmail SMTP ──► Management mailbox ──► Phone
            │
devops02 ───┘
```

SMTP credentials were protected in:

```text
/etc/msmtprc
```

with root ownership and restrictive permissions.

---

# 13. Add Automated Email Reporting

The Git-controlled update script was modified to generate management reports.

The report includes operational information such as:

```text
Host
Repository Refresh
Package Upgrade
APT Cache Cleanup
Packages Remaining Upgradeable
Reboot Required
Update Result
```

Subject examples:

```text
[Linux Fleet][devops01] Update SUCCESS

[Linux Fleet][devops02] Update SUCCESS - REBOOT REQUIRED

[Linux Fleet][locator01] Update FAILED
```

This allows the administrator to determine update status directly from a phone notification without first connecting to the server.

---

# 14. Canary Deployment

The modified email-reporting version was **not immediately deployed fleet-wide**.

`devops02` was selected as the canary.

Architecture:

```text
Git candidate
     │
     │ SCP
     ▼
/tmp/sys-update.sh
     │
     │ sudo install
     ▼
devops02
/usr/local/bin/sys-update.sh
```

The candidate was transferred from `ubuntu-devops01`:

```bash
scp \
~/dev/projects/engineering-notes/01-linux/Management-scripts/sys-update.sh \
brettcoder@192.168.1.137:/tmp/sys-update.sh
```

It was installed on `devops02`:

```bash
sudo install -m 755 \
/tmp/sys-update.sh \
/usr/local/bin/sys-update.sh
```

`install -m 755` both copied the artifact and established the desired permissions.

---

# 15. Verify Canary Artifact

The Git candidate was hashed on `ubuntu-devops01`:

```bash
sha256sum \
~/dev/projects/engineering-notes/01-linux/Management-scripts/sys-update.sh
```

The deployed artifact was hashed on `devops02`:

```bash
sha256sum /usr/local/bin/sys-update.sh
```

The hashes matched.

Therefore:

```text
Git candidate
      =
devops02 candidate
```

The canary server was running the exact artifact intended for testing.

---

# 16. Host Filesystem Context

During SHA-256 testing, an important filesystem concept was reinforced.

A pathname exists in the context of the host where the command is executed.

For example:

```text
ubuntu-devops01:
/home/brettcoder/dev/projects/engineering-notes/...
```

does not imply that the same path exists on:

```text
locator01
```

or:

```text
devops02
```

Always inspect the shell prompt:

```text
brettcoder@ubuntu-devops01
brettcoder@devops02
brettcoder@locator01
```

before multi-server operations.

---

# 17. Canary Runtime Test

The candidate was executed on `devops02`:

```bash
sudo /usr/local/bin/sys-update.sh
```

Runtime status:

```bash
echo $?
```

Log inspection:

```bash
sudo tail -40 /var/log/server-autoupdate.log
```

Results included:

```text
Package Upgrade: SUCCESS
APT Cache Cleanup: SUCCESS
Packages Remaining Upgradeable: 0
Reboot Required: YES
Update Result: SUCCESS
```

The script correctly detected a pending kernel transition.

---

# 18. Kernel Update Detection

The canary reported:

```text
Running kernel:
6.8.0-137-generic

Expected/new kernel:
6.8.0-138-generic
```

The reboot-triggering packages included:

```text
linux-image-6.8.0-138-generic
linux-base
```

The update itself succeeded.

However:

```text
Installed kernel
      ≠
Running kernel
```

until reboot.

The automated management email successfully reported:

```text
Update SUCCESS - REBOOT REQUIRED
```

---

# 19. Reboot Canary

`devops02` was rebooted.

After reconnection:

```bash
uname -r
```

returned:

```text
6.8.0-138-generic
```

Reboot status was checked:

```bash
test -f /var/run/reboot-required \
&& echo "REBOOT REQUIRED" \
|| echo "NO REBOOT REQUIRED"
```

Result:

```text
NO REBOOT REQUIRED
```

Canary lifecycle:

```text
Git candidate
      │
      ▼
Syntax validation
      │
      ▼
Deploy
      │
      ▼
SHA-256 verification
      │
      ▼
Execute
      │
      ▼
Update packages
      │
      ▼
Detect kernel update
      │
      ▼
Send management email
      │
      ▼
Controlled reboot
      │
      ▼
Verify new kernel
      │
      ▼
Verify reboot flag cleared
      │
      ▼
CANARY PASSED
```

---

# 20. Commit Validated Version

After successful canary validation, the artifact was suitable for becoming the authoritative version.

Workflow:

```bash
git status
```

Stage:

```bash
git add 01-linux/Management-scripts/sys-update.sh
```

Review:

```bash
git diff --staged
```

Commit:

```bash
git commit -m "Add automated fleet update email reporting"
```

Push:

```bash
git push
```

At this point:

```text
Git remote
    │
    ▼
validated sys-update.sh
    │
    ▼
AUTHORITATIVE VERSION
```

---

# 21. Fleet Rollout

The approved version was deployed across:

```text
devops01
devops02
locator01
```

Target state:

```text
                 Git
                  │
          authoritative hash
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
    devops01   devops02   locator01
        │         │         │
        └─────────┼─────────┘
                  ▼
            identical hash
```

SHA-256 validation confirmed consistent artifacts.

---

# 22. Fleet Functional Verification

The update script was executed and verified across the fleet.

Verification included:

```bash
sudo /usr/local/bin/sys-update.sh
```

Exit status:

```bash
echo $?
```

Logs:

```bash
sudo tail -40 /var/log/server-autoupdate.log
```

Management emails were received successfully.

Therefore the fleet demonstrated:

```text
Git-controlled artifact     ✓
Fleet deployment            ✓
Artifact integrity          ✓
Runtime execution           ✓
APT updates                 ✓
Logging                     ✓
Reboot detection            ✓
Email reporting             ✓
Management notification     ✓
```

---

# 23. Manual CI/CD Pipeline

The complete process performed during this lab represents a manual CI/CD-style workflow:

```text
Modify code
    │
    ▼
bash -n
    │
    ▼
Review diff
    │
    ▼
Canary deployment
    │
    ▼
SHA-256 validation
    │
    ▼
Runtime testing
    │
    ▼
Functional validation
    │
    ▼
Commit
    │
    ▼
Push
    │
    ▼
Fleet rollout
    │
    ▼
Post-deployment verification
```

This is important because future automation will replace a process that has already been manually understood.

---

# 24. Why Git Alone Is Not Fleet Management

Git answers:

> What version should exist?

Git does **not**, by itself, ensure that version exists on every managed server.

Therefore:

```text
Git
 │
 ▼
SOURCE OF TRUTH
```

requires:

```text
Deployment mechanism
```

to produce:

```text
Git desired state
       =
Fleet actual state
```

---

# 25. Why Manual Fleet Execution Does Not Scale

Current testing requires operations such as:

```bash
sudo /usr/local/bin/sys-update.sh
```

on each server individually.

For three systems this is manageable.

For:

```text
3 servers
10 servers
50 servers
500 servers
```

it becomes increasingly inefficient and error-prone.

Remote SSH execution can help:

```bash
ssh server 'sudo /usr/local/bin/sys-update.sh'
```

but building custom Bash loops around SSH eventually recreates functionality already provided by configuration-management platforms.

---

# 26. Transition to Ansible

The next architectural stage is:

```text
                   ubuntu-devops01
                    CONTROL NODE
                         │
                         │ Ansible
              ┌──────────┼──────────┐
              ▼          ▼          ▼
          devops01    devops02   locator01
```

Instead of manually:

```text
SSH → execute
SSH → execute
SSH → execute
```

the administrator will eventually execute:

```text
Ansible
   │
   ▼
linux_fleet
```

against an inventory of managed systems.

---

# 27. Desired-State Configuration

The future model becomes:

```text
Git
 │
 │ defines desired state
 ▼
Ansible
 │
 │ enforces desired state
 ▼
Linux Fleet
```

If:

```text
Git sys-update.sh = VERSION X
```

but:

```text
locator01 sys-update.sh = VERSION Y
```

Ansible can converge the system:

```text
VERSION Y
    │
    ▼
Ansible
    │
    ▼
VERSION X
```

Result:

```text
ACTUAL STATE = DESIRED STATE
```

---

# 28. Future CI/CD Architecture

Target:

```text
Administrator
     │
     ▼
Modify code
     │
     ▼
Git commit
     │
     ▼
Git push
     │
     ▼
┌────────────────────┐
│         CI         │
│                    │
│ bash -n            │
│ ShellCheck         │
│ security checks    │
│ automated tests    │
└─────────┬──────────┘
          │
         PASS
          │
          ▼
 Approved artifact
          │
          ▼
┌────────────────────┐
│         CD         │
│                    │
│ Ansible deployment │
└─────────┬──────────┘
          │
    ┌─────┼─────┐
    ▼     ▼     ▼
  dev1   dev2  locator
          │
          ▼
   email reporting
```

---

# 29. Command Reference Additions

## `find`

```bash
find PATH -name "filename"
```

Search the filesystem.

Example:

```bash
sudo find / -name "sys-update.sh" 2>/dev/null
```

---

## `pwd`

```bash
pwd
```

Print the current working directory.

---

## `scp`

```bash
scp SOURCE DESTINATION
```

Securely copy files using SSH.

---

## `sha256sum`

```bash
sha256sum FILE
```

Calculate a SHA-256 checksum.

Uses:

* Transfer verification
* Artifact verification
* Configuration-drift detection

---

## `git rev-parse --show-toplevel`

```bash
git rev-parse --show-toplevel
```

Display the repository root.

---

## `git status`

```bash
git status
```

Inspect working-tree and staging state.

---

## `git add`

```bash
git add FILE
```

Stage a change.

---

## `git diff --staged`

```bash
git diff --staged
```

Inspect the exact changes selected for the next commit.

---

## `bash -n`

```bash
bash -n SCRIPT
```

Parse a Bash script without executing it.

---

## `$?`

```bash
echo $?
```

Display the exit status of the immediately preceding command.

Typically:

```text
0       success
nonzero other/failure condition
```

---

## `install`

```bash
sudo install -m 755 SOURCE DESTINATION
```

Copy a file while applying specified permissions.

Used during deployment:

```bash
sudo install -m 755 \
/tmp/sys-update.sh \
/usr/local/bin/sys-update.sh
```

---

## `uname -r`

```bash
uname -r
```

Display the currently running Linux kernel.

---

## Reboot Requirement Test

```bash
test -f /var/run/reboot-required \
&& echo "REBOOT REQUIRED" \
|| echo "NO REBOOT REQUIRED"
```

Determine whether the system currently indicates that a reboot is required.

---

# 30. Key Lessons Learned

### Source control is not deployment

```text
Git = authoritative state

Deployment tooling = mechanism that applies state
```

### A successful update does not necessarily mean maintenance is finished

A kernel package can install successfully while the system continues running the old kernel.

Therefore:

```text
package installed
      ≠
kernel activated
```

### Validate before fleet deployment

The canary process prevented an untested change from immediately affecting every managed server.

### Hashes provide evidence

SHA-256 provided objective evidence that the intended artifact reached the intended host.

### Separate secrets from source code

SMTP credentials remain outside Git.

### Management notifications reduce unnecessary investigation

A useful alert should tell the administrator:

```text
WHAT system?
WHAT happened?
DID it succeed?
IS action required?
```

before the administrator needs to SSH into the machine.

### Automation should replace understood manual processes

The complete deployment process was performed manually before introducing configuration-management tooling.

---

# 31. RB-LINUX-011 Completion Checklist

```text
[✓] Locate production management script
[✓] Transfer artifact with SCP
[✓] Verify artifact with SHA-256
[✓] Inspect artifact for secrets
[✓] Establish Management-scripts repository location
[✓] Observe Git untracked state
[✓] Understand Git path presentation
[✓] Identify Git repository root
[✓] Stage artifact
[✓] Review staged changes
[✓] Validate Bash syntax
[✓] Establish Git as source of truth
[✓] Understand configuration drift
[✓] Configure SMTP on locator01
[✓] Configure SMTP on devops02
[✓] Configure SMTP on devops01
[✓] Verify management email delivery
[✓] Add automated email reporting
[✓] Select devops02 as canary
[✓] Deploy candidate to canary
[✓] Verify canary SHA-256
[✓] Execute canary
[✓] Detect kernel update
[✓] Receive automatic management email
[✓] Perform controlled reboot
[✓] Verify new running kernel
[✓] Verify reboot-required flag cleared
[✓] Commit validated version
[✓] Push authoritative version
[✓] Roll out approved artifact fleet-wide
[✓] Verify fleet hashes
[✓] Verify fleet runtime behavior
[✓] Verify fleet email reporting
```

---

# 32. Final Architecture

```text
                    GIT
             SOURCE OF TRUTH
                    │
                    │
             sys-update.sh
                    │
                    ▼
              Fleet rollout
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
    devops01     devops02    locator01
        │           │           │
        ▼           ▼           ▼
     APT update   APT update  APT update
        │           │           │
        ▼           ▼           ▼
   reboot check reboot check reboot check
        │           │           │
        └───────────┼───────────┘
                    │
                    ▼
                 msmtp
                    │
                    ▼
          Management mailbox
                    │
                    ▼
            Phone notification
```

---

# 33. Next Evolution

Manual fleet administration has now reached the point of diminishing returns.

The next runbook is:

```text
RB-LINUX-012-ansible-linux-fleet-management.md
```

Objective:

> Configure `ubuntu-devops01` as an Ansible control node, establish a managed Linux fleet inventory, validate centralized connectivity, and begin replacing repetitive per-server administration with controlled configuration management.

The existing update system will become the first real workload managed through Ansible:

```text
Git
 ↓
Ansible
 ↓
Linux Fleet
 ↓
Patch / Verify
 ↓
Email Report
```

---

## Status

**RB-LINUX-011: COMPLETE**
