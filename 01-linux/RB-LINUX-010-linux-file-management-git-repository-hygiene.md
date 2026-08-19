# RB-LINUX-010 — Linux File Management and Git Repository Hygiene

## Purpose

Practice Linux file and pathname management while standardizing the naming convention of engineering documentation stored in Git.

This exercise covered:

* Renaming files with `mv`
* Understanding relative and absolute paths
* Handling filenames containing spaces
* Understanding shell quoting
* Understanding backticks and command substitution
* Diagnosing hidden/leading whitespace in filenames
* Using `tree` and `ls` to inspect directory structure
* Understanding how filesystem renames are represented by Git
* Establishing a standardized runbook naming convention

---

## Environment

Repository:

```text
~/dev/projects/engineering-notes/
```

Linux runbook directory:

```text
~/dev/projects/engineering-notes/01-linux/
```

Working directory:

```bash
cd ~/dev/projects/engineering-notes/01-linux
```

---

# Objective

Existing Linux runbooks had inconsistent filenames.

Examples included:

```text
RB-LINUX-001 Linux identity groups shared directory
RB-LINUX-002
RB-LINUX-005 Processes and Resource Utilization
RB-LINUX-007-Disk capacity troubleshooting.md
RB-009-linux-fleet-automated-update-management.md
```

Problems included:

* Spaces in filenames
* Missing `.md` extensions
* Inconsistent capitalization
* Inconsistent runbook prefixes
* Inconsistent separators
* A filename containing an accidental leading space
* A filename containing an accidental trailing hyphen

The objective was to normalize these files without changing their contents.

---

# Target Naming Convention

Linux runbooks will use:

```text
RB-LINUX-###-descriptive-title.md
```

Example:

```text
RB-LINUX-010-linux-file-management-git-repository-hygiene.md
```

Standards:

```text
RB-LINUX      Runbook category
###           Three-digit sequence number
-             Word separator
lowercase     Descriptive filename
.md           Markdown document
```

Spaces should generally be avoided in repository filenames.

---

# Inspect Directory Structure

The `tree` command was used to inspect the current directory:

```bash
tree
```

Example:

```text
.
├── RB-LINUX-001-linux-identity-groups-shared-directory.md
├── RB-LINUX-002-linux-identity-users-groups-permissions.md
├── RB-LINUX-003-service-management-systemd.md
├── RB-LINUX-004-logs-journald-troubleshooting.md
├── RB-LINUX-005-processes-resource-utilization.md
├── RB-LINUX-006-systemd-service-administration.md
├── RB-LINUX-007-disk-capacity-troubleshooting.md
└── RB-LINUX-009-linux-fleet-automated-update-management.md
```

`tree` provides a hierarchical representation of files and directories and is useful for repository inspection.

---

# Rename Files with `mv`

Linux uses `mv` both to move and rename filesystem objects.

Syntax:

```bash
mv SOURCE DESTINATION
```

Example:

```bash
mv RB-LINUX-002 \
RB-LINUX-002-linux-identity-users-groups-permissions.md
```

Conceptually:

```text
SOURCE PATH
    |
    | mv
    v
DESTINATION PATH
```

No separate Linux `rename` operation is required for basic file renaming.

---

# Filenames Containing Spaces

The shell normally uses whitespace to separate command arguments.

This command:

```bash
nano RB-009 Email Notification.md
```

does not represent one filename to the shell.

It is parsed as multiple arguments.

Use quotes:

```bash
nano "RB-009 Email Notification.md"
```

Single quotes also work:

```bash
nano 'RB-009 Email Notification.md'
```

Spaces can alternatively be escaped:

```bash
nano RB-009\ Email\ Notification.md
```

For Git repositories, filenames without spaces are generally easier to manipulate:

```text
RB-LINUX-009-linux-fleet-automated-update-management.md
```

---

# Shell Quoting

## Double Quotes

```bash
"filename with spaces"
```

Double quotes preserve spaces while still allowing shell expansion such as variables.

Example:

```bash
FILE="report.md"

echo "$FILE"
```

---

## Single Quotes

```bash
'filename with spaces'
```

Single quotes treat their contents literally.

Example:

```bash
mv 'old file.md' 'new file.md'
```

---

# Backticks Are Not Quotes

An attempted command was:

```bash
mv RB-LINUX-002 `RB-LINUX-002-linux-identity-users-groups-permissions.md`
```

This generated:

```text
RB-LINUX-002-linux-identity-users-groups-permissions.md: command not found
mv: missing destination file operand
```

The reason is that backticks perform **command substitution**.

The shell interpreted:

```bash
`RB-LINUX-002-linux-identity-users-groups-permissions.md`
```

as:

> Execute this text as a command and substitute its output into the command line.

---

# Command Substitution

Legacy syntax:

```bash
RESULT=`command`
```

Preferred modern syntax:

```bash
RESULT=$(command)
```

Example:

```bash
CURRENT_KERNEL=$(uname -r)
```

Then:

```bash
echo "$CURRENT_KERNEL"
```

Backticks should therefore **not** be used merely to protect filenames containing spaces.

---

# Relative vs Absolute Paths

The repository was located at:

```text
/home/brettcoder/dev/projects/engineering-notes/01-linux
```

Because the shell was already inside that directory, a relative pathname was sufficient:

```bash
mv RB-LINUX-002 new-name.md
```

There was no need to specify:

```text
/home/brettcoder/dev/projects/engineering-notes/01-linux/...
```

---

## Relative Path

Example:

```bash
mv RB-LINUX-002 new-name.md
```

The pathname is interpreted relative to the current working directory.

---

## Absolute Path

Example:

```text
/home/brettcoder/dev/projects/engineering-notes/01-linux/RB-LINUX-002
```

An absolute pathname begins at:

```text
/
```

and identifies the complete filesystem location.

---

# Path Troubleshooting

An attempted path used:

```text
/dev/projects/...
```

However, the repository actually existed under:

```text
/home/brettcoder/dev/projects/...
```

These are entirely different locations.

```text
/
├── dev/
│
└── home/
    └── brettcoder/
        └── dev/
            └── projects/
```

Linux pathnames must identify the exact filesystem object.

---

# Understanding `cannot stat`

An attempted rename returned:

```text
mv: cannot stat 'RB-LINUX-006-systemd-service-administration-':
No such file or directory
```

The file appeared to exist.

Inspection with `tree` revealed:

```text
├──  RB-LINUX-006-systemd-service-administration-
```

The actual filename contained a **leading space**.

Therefore:

```text
RB-LINUX-006-systemd-service-administration-
```

and:

```text
 RB-LINUX-006-systemd-service-administration-
```

are different filenames.

The error therefore did not mean that no similar file existed.

It meant:

> The exact pathname supplied to `mv` could not be found.

---

# Correcting Leading Whitespace

The leading space was included inside quotes:

```bash
mv " RB-LINUX-006-systemd-service-administration-" \
RB-LINUX-006-systemd-service-administration.md
```

The space immediately following the opening quote was intentional.

Result:

```text
RB-LINUX-006-systemd-service-administration.md
```

---

# Inspect Difficult Filenames

Ordinary:

```bash
ls
```

may make whitespace problems difficult to identify.

Use:

```bash
ls -lb
```

The `-b` option escapes special characters in filenames, making unusual pathnames easier to diagnose.

Another useful technique:

```bash
printf '<%s>\n' *
```

Example:

```text
<RB-LINUX-005-processes-resource-utilization.md>
< RB-LINUX-006-systemd-service-administration->
<RB-LINUX-007-disk-capacity-troubleshooting.md>
```

The delimiters make leading/trailing whitespace easier to see.

---

# Tab Completion

Shell tab completion can reduce pathname errors.

Instead of manually typing an unusual filename, begin entering it and use:

```text
TAB
```

to allow the shell to complete or escape the pathname.

This is particularly useful for:

* Long filenames
* Spaces
* Special characters
* Deep directory paths
* Avoiding typing mistakes

---

# Git and Filesystem Renames

Files were renamed using Linux:

```bash
mv
```

rather than a Git-specific operation.

Git compares the working tree against its recorded repository state and can detect that content has moved from one pathname to another.

After renaming files:

```bash
git status
```

should be used before staging or committing.

---

# Inspect Git Changes

## Repository Status

```bash
git status
```

Purpose:

> What has changed in my working tree?

---

## Change Statistics

```bash
git diff --stat
```

Purpose:

> Give me a summary of the current changes.

---

## Filename/Status Changes

```bash
git diff --name-status
```

Purpose:

> Which files changed and what type of change occurred?

---

# Stage Renames

After verifying the repository:

```bash
git add -A
```

`-A` stages:

* New files
* Modified files
* Deleted files

This allows Git to recognize the old pathname disappearing and the new pathname appearing.

Git may subsequently display the operation as a rename.

---

# Git Rename Detection

Conceptually:

```text
Working Tree

old-name.md
     |
     | mv
     v
new-name.md
     |
     v
git status
     |
     v
Git compares content
     |
     v
rename detected
```

Git primarily tracks content and repository state rather than depending on the administrator explicitly declaring every filesystem rename.

---

# Verify Before Commit

Recommended workflow:

```text
Rename files
     |
     v
tree
     |
     v
git status
     |
     v
git diff --stat
     |
     v
git diff --name-status
     |
     v
Review
     |
     v
git add -A
     |
     v
git status
     |
     v
Commit
```

Do not immediately commit filesystem changes without reviewing Git's interpretation of them.

---

# Repository Hygiene

A consistent naming convention improves:

* CLI usability
* Git operations
* Shell scripting
* Markdown links
* Automation
* CI/CD workflows
* Searchability
* Repository readability

Preferred:

```text
RB-LINUX-005-processes-resource-utilization.md
```

Avoid:

```text
RB-LINUX-005 Processes and Resource Utilization
```

The latter is valid Linux, but requires additional shell quoting and increases the chance of automation errors.

---

# Current Repository Convention

```text
01-linux/
│
├── RB-LINUX-001-*.md
├── RB-LINUX-002-*.md
├── RB-LINUX-003-*.md
├── RB-LINUX-004-*.md
├── RB-LINUX-005-*.md
├── RB-LINUX-006-*.md
├── RB-LINUX-007-*.md
├── RB-LINUX-009-*.md
└── RB-LINUX-010-linux-file-management-git-repository-hygiene.md
```

RB-LINUX-008 remains intentionally unassigned until the previous lab history is reviewed. Do not renumber unrelated documentation solely to eliminate the sequence gap.

---

# Command Reference

## `tree`

```bash
tree
```

Displays files and directories hierarchically.

---

## `mv`

```bash
mv SOURCE DESTINATION
```

Moves or renames files and directories.

Rename:

```bash
mv old.md new.md
```

Move:

```bash
mv runbook.md ./archive/
```

Move and rename:

```bash
mv runbook.md ./archive/RB-LINUX-010.md
```

---

## `ls -lb`

```bash
ls -lb
```

Displays directory contents while escaping special characters in filenames.

Useful for identifying unusual pathnames.

---

## `printf`

```bash
printf '<%s>\n' *
```

Can expose filename boundaries and make leading/trailing whitespace visible.

---

## `git status`

```bash
git status
```

Displays the state of the working tree and staging area.

---

## `git diff --stat`

```bash
git diff --stat
```

Provides a statistical summary of unstaged changes.

---

## `git diff --name-status`

```bash
git diff --name-status
```

Shows changed filenames and their status.

---

## `git add -A`

```bash
git add -A
```

Stages additions, modifications, and deletions.

Useful when filesystem operations include file renames.

---

# Troubleshooting Decision Tree

```text
Command says file does not exist
            |
            v
      Does `ls` show it?
        /         \
      NO           YES
      |             |
Check directory    Check exact pathname
      |             |
     pwd         +-- case
                 +-- spaces
                 +-- leading whitespace
                 +-- trailing whitespace
                 +-- special characters
                 |
                 v
               ls -lb
                 |
                 v
          printf '<%s>\n' *
                 |
                 v
          Use quotes or TAB
                 |
                 v
              Retry
```

---

# Lessons Learned

### Linux pathnames are exact

A visually similar filename is not necessarily the same pathname.

Case, whitespace, and special characters matter.

### Quotes and backticks perform different functions

```text
'...'   literal quoting
"..."   quoting with expansion
`...`   command substitution
$(...)  modern command substitution
```

### `mv` handles renaming

Linux treats a rename as moving an object from one pathname to another.

### Error messages describe the requested operation

```text
cannot stat
```

does not necessarily mean that nothing resembling the filename exists.

It means the exact pathname supplied could not be resolved.

### Repository hygiene matters for automation

A naming convention that is merely cosmetic today can become operationally important once CI/CD, scripts, and configuration-management tooling begin consuming the repository.

---

# Status

**RB-LINUX-010: COMPLETE**

Skills exercised:

* Linux pathname navigation
* File renaming
* Shell quoting
* Command substitution recognition
* Whitespace troubleshooting
* Relative vs absolute paths
* Repository naming conventions
* Git working-tree inspection
* Repository hygiene
