RB-LINUX-011 — Git Source of Truth and Fleet Deployment

## Purpose

Establish Git as the authoritative source for Linux management scripts and develop a controlled workflow for validating, versioning, deploying, and verifying those scripts across a fleet of Linux servers.

This runbook introduces the foundations of:

* Source control
* Artifact integrity
* Git staging and commits
* Single source of truth
* Configuration drift
* Desired-state configuration
* Manual deployment
* CI/CD
* Future Ansible configuration management

---

## Environment

Current Linux fleet:

```text
ubuntu-devops01
    │
    ├── Git repository / management host
    │
    └── Monitoring infrastructure

devops02
    │
    └── Managed Linux server

locator01
    │
    ├── Managed Linux server
    └── Original sys-update.sh canary
```

Git repository:

```text
~/dev/projects/engineering-notes/
```

Management script:

```text
01-linux/Management-scripts/sys-update.sh
```

Runtime location:

```text
/usr/local/bin/sys-update.sh
```

---

# 1. Establish the Production Artifact

The tested update script originally existed on `locator01`:

```text
/usr/local/bin/sys-update.sh
```

The script first had to be located.

Command used:

```bash
sudo find / -name "sys-update.sh" 2>/dev/null
```

### Command breakdown

```text
find /
 │
 └── search beginning at filesystem root

-name "sys-update.sh"
 │
 └── locate this exact filename

2>/dev/null
 │
 └── redirect stderr to /dev/null
```

This suppressed irrelevant permission errors while searching.

---

# 2. Determine Path

The working directory was identified with:

```bash
pwd
```

`pwd` means:

```text
print working directory
```

This was used to determine the absolute destination path for the Git repository.

---

# 3. Transfer the Tested Artifact

The production-tested script was transferred from `locator01` to `ubuntu-devops01` using SCP:

```bash
scp brettcoder@192.168.1.144:/usr/local/bin/sys-update.sh \
/home/brettcoder/dev/projects/engineering-notes/01-linux/Management-scripts
```

Architecture:

```text
locator01
192.168.1.144
     │
     │ SSH/SCP
     ▼
ubuntu-devops01
     │
     ▼
engineering-notes/
└── 01-linux/
    └── Management-scripts/
        └── sys-update.sh
```

Interactive SSH authentication was supplied to authorize the transfer.

---

# 4. Verify Artifact Integrity

The source and destination artifacts were compared using SHA-256.

On `locator01`:

```bash
sha256sum /usr/local/bin/sys-update.sh
```

On `ubuntu-devops01`:

```bash
sha256sum \
~/dev/projects/engineering-notes/01-linux/Management-scripts/sys-update.sh
```

The hashes matched.

Therefore:

```text
SOURCE
sys-update.sh
     │
     ▼
 SHA-256 A
     │
     │
     ├──────── MATCH ────────┐
     │                       │
     ▼                       ▼
verified                 SHA-256 B
                             ▲
                             │
                        sys-update.sh
                        DESTINATION
```

Matching SHA-256 hashes prove that the transferred files are byte-for-byte identical.

---

# 5. Secret Review

The script was inspected before placing it under source control.

No:

* Passwords
* SMTP App Passwords
* API keys
* Authentication tokens
* Private keys
* Other credentials

were embedded in `sys-update.sh`.

SMTP credentials remain separate in:

```text
/etc/msmtprc
```

That file must **not** be committed to Git.

Operational principle:

```text
CODE       → Git
SAFE CONFIG → Git where appropriate
SECRETS    → outside Git
LOGS       → server/runtime
```

---

# 6. Observe the Untracked Artifact

Before staging:

```bash
git status
```

reported the new management script as untracked.

An important Git behavior was discovered.

From:

```text
engineering-notes/01-linux/Management-scripts/
```

Git displayed:

```text
./
```

From:

```text
engineering-notes/01-linux/
```

Git displayed:

```text
Management-scripts/
```

From the repository root:

```text
engineering-notes/
```

Git could display:

```text
01-linux/Management-scripts/sys-update.sh
```

The artifact did not move.

The **point of reference changed**.

---

# 7. Locate the Git Repository Root

From anywhere inside the repository:

```bash
git rev-parse --show-toplevel
```

identifies the Git repository root.

Conceptually:

```text
engineering-notes/          ← Git root
│
├── 01-linux/
│   │
│   └── Management-scripts/
│       └── sys-update.sh
│
├── 02-networking/
│
└── ...
```

Git operations executed within these subdirectories still operate within the same repository.

---

# 8. Git File States

The new script initially existed as:

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

Git lifecycle:

```text
Working Directory
       │
       │ git add
       ▼
   Staging Area
       │
       │ git commit
       ▼
Local Repository
       │
       │ git push
       ▼
Remote Repository
```

---

# 9. Understand the Staging Area

`git add` does **not** commit a file.

It tells Git:

> Include this version of this file in the next commit.

Therefore:

```text
UNTRACKED
    │
    │ git add
    ▼
STAGED
    │
    │ git commit
    ▼
TRACKED / COMMITTED
```

The staging area provides an opportunity to inspect exactly what will enter repository history.

---

# 10. Review Staged Changes

Command:

```bash
git diff --staged
```

Equivalent:

```bash
git diff --cached
```

This answers:

> What changes am I about to commit relative to the previous commit?

Because `sys-update.sh` was a completely new file, Git displayed essentially the entire script.

Lines beginning with:

```text
+
```

represented additions.

---

# 11. `cat` vs `git diff --staged`

These commands may appear similar when adding a new file but answer different questions.

### `cat`

```bash
cat sys-update.sh
```

Answers:

> What is currently inside this filesystem object?

### Git

```bash
git diff --staged
```

Answers:

> What changes are currently staged for the next repository commit?

That distinction becomes more obvious when modifying an existing tracked file.

---

# 12. Bash Syntax Validation

Before committing:

```bash
bash -n 01-linux/Management-scripts/sys-update.sh
```

Then:

```bash
echo $?
```

Result:

```text
0
```

This means:

> Bash successfully parsed the script without detecting syntax errors.

It does **not** prove:

* The script executes successfully
* Every command exists
* The script's logic is correct
* The update succeeds
* The intended operational outcome occurs

Validation hierarchy:

```text
bash -n
   │
   ▼
SYNTAX VALIDATION
Can Bash parse it?
   │
   ▼
RUNTIME VALIDATION
Can it execute?
   │
   ▼
FUNCTIONAL VALIDATION
Does it accomplish the objective?
```

The artifact had previously been functionally tested on `locator01`.

---

# 13. Manual CI Concept

The workflow performed manually represents the beginning of a CI process:

```text
Artifact
   │
   ▼
Functional test
   │
   ▼
Transfer
   │
   ▼
SHA-256 integrity validation
   │
   ▼
Secret inspection
   │
   ▼
Bash syntax validation
   │
   ▼
Git staging
   │
   ▼
Staged-content review
   │
   ▼
Commit
```

Future CI tooling will automate many of these checks.

---

# 14. Git as the Single Source of Truth

The central operational policy is:

> **The canonical copy of `sys-update.sh` lives in Git. Server copies are deployed artifacts derived from Git.**

Therefore:

```text
Git repository copy
        =
AUTHORITATIVE SOURCE
```

while:

```text
/usr/local/bin/sys-update.sh
        =
DEPLOYED RUNTIME COPY
```

---

# 15. Change-Control Policy

Once Git becomes authoritative, administrators should avoid directly editing:

```bash
sudo nano /usr/local/bin/sys-update.sh
```

on individual fleet servers.

Instead:

```text
Need modification
      │
      ▼
Edit Git copy
      │
      ▼
Validate
      │
      ▼
Review diff
      │
      ▼
Commit
      │
      ▼
Push
      │
      ▼
Deploy
      │
      ▼
Verify
```

This ensures the same approved version can be distributed across the fleet.

---

# 16. Configuration Drift

Suppose Git contains:

```text
sys-update.sh
SHA256 = ABC123
```

but `locator01` contains:

```text
sys-update.sh
SHA256 = DEF456
```

Then:

```text
ABC123 != DEF456
```

The server no longer matches the authoritative configuration.

This is:

```text
CONFIGURATION DRIFT
```

Common causes include:

* Manual server edits
* Failed deployments
* Different deployment versions
* Emergency modifications
* Unauthorized changes

---

# 17. Drift Detection

The Git artifact can be hashed:

```bash
sha256sum \
01-linux/Management-scripts/sys-update.sh
```

The deployed artifact can be checked remotely:

```bash
ssh locator01 sha256sum /usr/local/bin/sys-update.sh
```

Comparison:

```text
Git hash
   │
   ├──── matches ────► compliant
   │
   └──── differs ────► configuration drift
```

The SHA-256 technique originally used to verify SCP integrity therefore also becomes useful for configuration-management validation.

---

# 18. Manual Deployment Model

The next stage is manual fleet deployment:

```text
                     GIT
                      │
              approved artifact
                      │
                      ▼
               ubuntu-devops01
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
     devops01      devops02    locator01
          │           │           │
          └───────────┼───────────┘
                      │
                  SHA-256
                   verify
```

This allows the administrator to understand the deployment process before automating it.

---

# 19. Configuration Management

The manual deployment process will eventually be replaced by Ansible:

```text
Git
 │
 ▼
Ansible control node
 │
 ├────────► devops01
 │
 ├────────► devops02
 │
 └────────► locator01
```

Ansible will enforce the desired state defined by the Git-controlled configuration.

---

# 20. Desired-State Configuration

Desired state asks:

> What **should** this system look like?

Example:

```text
Git desired state:
sys-update.sh = VERSION X

Server actual state:
sys-update.sh = VERSION Y
```

Configuration management detects the difference and converges the server:

```text
VERSION Y
    │
    │ configuration management
    ▼
VERSION X
```

Result:

```text
ACTUAL STATE = DESIRED STATE
```

---

# 21. Future CI/CD Architecture

The target architecture is:

```text
Administrator
      │
      ▼
Modify sys-update.sh
      │
      ▼
Git commit / push
      │
      ▼
┌──────────────────────┐
│          CI          │
│                      │
│ bash -n              │
│ ShellCheck           │
│ security checks      │
│ automated tests      │
└──────────┬───────────┘
           │
          PASS
           │
           ▼
      Approved artifact
           │
           ▼
┌──────────────────────┐
│          CD          │
│                      │
│ Ansible deployment   │
└──────────┬───────────┘
           │
     ┌─────┼─────┐
     ▼     ▼     ▼
   dev1   dev2  locator
```

---

# 22. Why Not `git pull` Everywhere?

It is technically possible to install Git on every server, clone the repository, and execute:

```bash
git pull
```

This is not the preferred long-term architecture.

It would require managed servers to contain:

* Git tooling
* Repository state
* Branch information
* Potential Git credentials
* Development-oriented working trees

Instead:

```text
Git
 │
 ▼
Deployment controller
 │
 ▼
approved artifact
 │
 ▼
Runtime server
```

The managed server receives only what it needs.

---

# 23. Manual → Automated Progression

Training progression:

```text
STAGE 1

Git
 │
 ▼
Administrator
 │
 ▼
SCP
 │
 ▼
Servers
```

Then:

```text
STAGE 2

Git
 │
 ▼
Ansible
 │
 ▼
Servers
```

Eventually:

```text
STAGE 3

Git push
 │
 ▼
CI validation
 │
 ▼
Approved change
 │
 ▼
Ansible / CD
 │
 ▼
Fleet
```

Manual administration is intentionally being learned before automation.

---

# 24. Command Reference Additions

### `find`

```bash
find PATH -name "filename"
```

Search for filesystem objects.

Example:

```bash
sudo find / -name "sys-update.sh" 2>/dev/null
```

---

### `pwd`

```bash
pwd
```

Print the current working directory.

---

### `scp`

```bash
scp SOURCE DESTINATION
```

Securely copy files using SSH.

Remote source example:

```bash
scp user@server:/path/file /local/path/
```

---

### `sha256sum`

```bash
sha256sum FILE
```

Calculate a SHA-256 checksum.

Uses include:

* Transfer validation
* Artifact integrity
* Drift detection

---

### `git rev-parse --show-toplevel`

```bash
git rev-parse --show-toplevel
```

Display the root directory of the current Git repository.

---

### `git add`

```bash
git add FILE
```

Stage a change for the next commit.

---

### `git diff --staged`

```bash
git diff --staged
```

Display changes currently staged for the next commit.

---

### `bash -n`

```bash
bash -n SCRIPT
```

Parse a Bash script without executing it.

Used for syntax validation.

---

### `$?`

```bash
echo $?
```

Display the exit status of the previously executed command.

Convention:

```text
0       success
nonzero failure/other condition
```

Exact nonzero meanings depend on the command.

---

# 25. Operational Lessons

### Git does not automatically deploy files

Git provides version control and an authoritative source.

A separate deployment mechanism distributes the approved artifact.

### Source and runtime should be distinguished

```text
Git copy       → source
Server copy    → deployment
```

### Direct edits create drift

Changing a managed server without updating the authoritative source can cause:

```text
desired state != actual state
```

### Validation has multiple layers

```text
syntax correct
      ≠
execution successful
      ≠
functionally correct
```

Each provides different evidence.

### Automation should replace understood manual processes

The deployment workflow is being performed manually before introducing Ansible or CI/CD.

This makes the purpose of later automation explicit.

---

# 26. RB-LINUX-011 Progress

Completed:

```text
[✓] Locate production sys-update.sh
[✓] Determine source pathname
[✓] Create Management-scripts directory
[✓] Transfer artifact with SCP
[✓] Authenticate transfer through SSH
[✓] Verify destination artifact
[✓] Compare SHA-256 hashes
[✓] Confirm byte-for-byte integrity
[✓] Inspect script for embedded credentials
[✓] Observe Git untracked state
[✓] Investigate Git relative pathname behavior
[✓] Identify repository root
[✓] Stage management script
[✓] Understand staging area
[✓] Review staged content
[✓] Validate Bash syntax
[✓] Establish Git source-of-truth model
[✓] Understand configuration drift
[✓] Understand desired-state configuration
[✓] Establish manual → Ansible → CI/CD progression
```

Next:

```text
[ ] Commit authoritative artifact
[ ] Push Git repository
[ ] Deploy Git version to devops01
[ ] Deploy Git version to devops02
[ ] Re-deploy Git version to locator01
[ ] Verify SHA-256 across entire fleet
[ ] Execute controlled patch test
[ ] Integrate fleet email reporting
[ ] Introduce Ansible
[ ] Automate deployment
[ ] Introduce CI validation
```

---

# Next Operational Exercise

```text
             Git-controlled
              sys-update.sh
                    │
             MANUAL DEPLOYMENT
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    devops01     devops02    locator01
        │           │           │
        └───────────┼───────────┘
                    ▼
              SHA-256 verify
                    │
                    ▼
             execute / test
                    │
                    ▼
              email reports
```

**Next task:** deploy the Git-controlled artifact across the Linux fleet manually and prove that every managed server is running the same version.

That gives us the hands-on deployment experience we need before we allow Ansible to do it for us.
