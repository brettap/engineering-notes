# GIT-001 — New Repository Setup and Conflict Troubleshooting

## Purpose

Document the process for creating a new Git repository from an existing project directory, connecting it to a GitHub remote repository, diagnosing repository configuration, and resolving GitHub email privacy push failures.

This runbook was developed while placing the `locator-platform` application under Git source control.

---

## Environment

**Host:** `locator01`  
**Project:** `locator-platform`  
**Project directory:**

```bash
/opt/locator-platform
```

**Primary branch:**

```text
main
```

**Remote repository:**

```text
brettap/locator-platform
```

---

# 1. Git Mental Model

Git source control consists of several distinct layers:

```text
Working Directory
      │
      │ git add
      ▼
Staging Area
      │
      │ git commit
      ▼
Local Git Repository
      │
      │ git push
      ▼
Remote Git Repository
      │
      ▼
GitHub
```

These components should not be treated as the same thing.

## Working Directory

The working directory contains the actual project files.

Example:

```text
/opt/locator-platform/
├── backend/
├── frontend/
├── infrastructure/
├── scripts/
├── docs/
├── tests/
├── requirements.txt
└── .gitignore
```

## Local Repository

Running:

```bash
git init
```

creates:

```text
/opt/locator-platform/.git/
```

The `.git` directory contains the repository metadata, including:

- commit history
- branches
- references
- repository configuration
- remote definitions

The presence of `.git` turns the project directory into a Git repository.

## Remote Repository

The remote repository is a separate Git repository hosted elsewhere, such as GitHub.

The local repository must explicitly be told where its remote repository exists.

Example:

```bash
git remote add origin <repository-url>
```

`origin` is the conventional name assigned to the primary remote repository.

---

# 2. Python Virtual Environments and Git

The Locator Platform uses Python, FastAPI, and a Python virtual environment.

Example shell:

```bash
(.venv) brettcoder@locator01:/opt/locator-platform$
```

The Python virtual environment is **not required for Git operations**.

The two systems perform different functions:

```text
Python virtual environment
        │
        ├── python
        ├── pip
        ├── FastAPI
        └── Python dependencies

Git repository
        │
        ├── files
        ├── commits
        ├── branches
        ├── history
        └── remotes
```

Git commands work whether `.venv` is active or not.

To leave the Python virtual environment:

```bash
deactivate
```

This does not affect the Git repository.

---

# 3. Creating a Repository From Existing Files

When project files already exist locally, enter the project's root directory first.

```bash
cd /opt/locator-platform
```

Verify:

```bash
pwd
```

Expected:

```text
/opt/locator-platform
```

Initialize the repository:

```bash
git init
```

Standardize the primary branch:

```bash
git branch -M main
```

Check repository status:

```bash
git status
```

Stage files:

```bash
git add .
```

Create the initial commit:

```bash
git commit -m "Initial locator-platform backend setup"
```

---

# 4. Connecting the Local Repository to GitHub

Creating a repository on GitHub does **not automatically connect** the local Linux repository to it.

The relationship must be configured using a Git remote.

Example:

```bash
git remote add origin <repository-url>
```

Verify:

```bash
git remote -v
```

Expected structure:

```text
origin  <repository-url> (fetch)
origin  <repository-url> (push)
```

Then push:

```bash
git push -u origin main
```

The `-u` option establishes the upstream relationship between:

```text
local main
     │
     ▼
origin/main
```

After the upstream relationship exists, subsequent pushes can normally use:

```bash
git push
```

and updates can normally use:

```bash
git pull
```

---

# 5. Creating a Repository vs. Cloning a Repository

Two workflows must be distinguished.

## Existing Local Project

If files already exist locally:

```bash
cd /path/to/project
git init
git add .
git commit
git remote add origin <repository-url>
git push -u origin main
```

## Existing Remote Repository

If the repository already exists remotely and needs to be placed on another machine, normally use:

```bash
git clone <repository-url>
```

`git clone` automatically creates:

- the project directory
- the `.git` repository
- the local working copy
- the `origin` remote
- repository history
- the checked-out branch

Therefore, do not normally run `git init` after cloning an existing repository.

---

# 6. Repository Diagnostic Commands

When entering an unfamiliar project directory, use the following commands before changing anything.

## Determine Current Directory

```bash
pwd
```

Answers:

> Where am I in the filesystem?

---

## Determine Repository Status

```bash
git status
```

Answers:

- Am I inside a Git repository?
- What branch am I on?
- Are files modified?
- Are files staged?
- Are files untracked?
- Is the working tree clean?

Example:

```text
On branch main
nothing to commit, working tree clean
```

---

## Find Repository Root

```bash
git rev-parse --show-toplevel
```

Example:

```text
/opt/locator-platform
```

This is particularly useful when working inside nested directories.

For example, the shell may currently be in:

```text
/opt/locator-platform/backend/core/auth
```

while:

```bash
git rev-parse --show-toplevel
```

returns:

```text
/opt/locator-platform
```

This means `/opt/locator-platform` is the actual Git repository root.

---

## Determine Current Branch

```bash
git branch --show-current
```

Expected:

```text
main
```

---

## Examine Configured Remotes

```bash
git remote -v
```

Example:

```text
origin  <repository-url> (fetch)
origin  <repository-url> (push)
```

---

# 7. Duplicate Remote Discovered

During repository setup, two remote names were found pointing to the same GitHub repository:

```text
brettap  <repository-url> (fetch)
brettap  <repository-url> (push)
origin   <repository-url> (fetch)
origin   <repository-url> (push)
```

This configuration is unnecessary.

Although Git supports multiple remotes, duplicate remotes pointing to the same repository can cause administrative confusion.

The conventional primary remote name is:

```text
origin
```

Remove the unnecessary remote:

```bash
git remote remove brettap
```

Verify:

```bash
git remote -v
```

Expected:

```text
origin  <repository-url> (fetch)
origin  <repository-url> (push)
```

---

# 8. GitHub Push Failure — GH007

The initial push failed with:

```text
remote: error: GH007: Your push would publish a private email address.
remote: You can make your email public or disable this protection
remote: by visiting GitHub email settings.

! [remote rejected] main -> main
(push declined due to email privacy restrictions)

error: failed to push some refs
```

## Root Cause

Git commits contain author metadata.

Each commit records information including:

```text
Author Name
Author Email
Commit Message
Timestamp
Commit Contents
```

The existing commit contained a private email address.

Verification:

```bash
git log -1 --format='Author: %an <%ae>'
```

Result:

```text
Author: Brett Pointer <4techworks@gmail.com>
```

GitHub was configured with:

```text
Keep my email addresses private
```

and:

```text
Block command line pushes that expose my email
```

Both privacy controls were enabled.

GitHub therefore rejected the commit because accepting it would expose the private email address in repository commit history.

---

# 9. GitHub Noreply Email

GitHub provides a private `noreply` email address that can be used for Git commit attribution without publishing the account's private email address.

The account's GitHub-generated address was identified in:

```text
GitHub
→ Settings
→ Emails
```

Format:

```text
<ID>+<username>@users.noreply.github.com
```

For this environment:

```text
94316117+brettap@users.noreply.github.com
```

---

# 10. Configure Git Commit Email

Configure the repository to use the GitHub noreply address:

```bash
git config user.email "94316117+brettap@users.noreply.github.com"
```

Verify:

```bash
git config --get user.email
```

Result:

```text
94316117+brettap@users.noreply.github.com
```

This configuration was made at the **repository level** rather than globally.

Repository-level configuration affects the current repository.

Global configuration would use:

```bash
git config --global user.email "address@example.com"
```

Use global configuration only when the same identity should be used for repositories across the user's account.

---

# 11. Critical Discovery — Git Configuration Does Not Rewrite Existing Commits

After changing the configured email:

```bash
git config --get user.email
```

returned:

```text
94316117+brettap@users.noreply.github.com
```

However:

```bash
git log -1 --format='Author: %an <%ae>'
```

still returned:

```text
Author: Brett Pointer <4techworks@gmail.com>
```

This behavior is expected.

## Why

`git config user.email` determines the identity Git should use when creating **future commits**.

It does not modify existing commit history.

Conceptually:

```text
Git configuration
      │
      │ git commit
      ▼
Commit created
      │
      ├── author name
      ├── author email
      ├── timestamp
      └── contents
```

Once the commit exists, changing Git configuration does not alter the metadata already stored inside that commit.

---

# 12. Correcting the Existing Commit

Because the incorrect email existed in the latest commit and the repository had not yet been successfully pushed, the commit could safely be amended.

Command:

```bash
git commit --amend --reset-author --no-edit
```

Options:

### `--amend`

Replace the most recent commit with a newly generated commit.

### `--reset-author`

Use the currently configured Git author identity.

### `--no-edit`

Preserve the existing commit message.

The command therefore means:

> Recreate the latest commit using the currently configured author identity without changing its commit message.

Verify:

```bash
git log -1 --format='Author: %an <%ae>'
```

Expected:

```text
Author: Brett Pointer <94316117+brettap@users.noreply.github.com>
```

---

# 13. Push the Corrected Repository

After correcting the author identity and removing the duplicate remote:

```bash
git push -u origin main
```

The push succeeded.

The local repository was now linked and synchronized with the GitHub repository.

---

# 14. Important Concept — A Commit Is a Historical Object

One of the major lessons from this incident is that a Git commit is more than a collection of changed files.

A commit contains historical metadata.

Simplified:

```text
COMMIT
├── file snapshot
├── parent commit
├── author
├── author email
├── committer
├── timestamp
└── commit message
```

Changing:

```bash
git config user.email
```

does not modify historical commits.

Instead:

```text
Change Git config
        │
        ▼
Future commits use new configuration

Existing commits
        │
        └── remain unchanged
```

Amending a commit actually creates a replacement commit with updated metadata.

---

# 15. Repository Setup Decision Tree

```text
START
  │
  ▼
Do project files already exist locally?
  │
  ├── YES
  │     │
  │     ▼
  │   cd /path/to/project
  │     │
  │     ▼
  │   Is it already a Git repository?
  │     │
  │     ├── NO → git init
  │     │
  │     └── YES → Do NOT git init again
  │
  │
  └── NO
        │
        ▼
Does repository already exist remotely?
        │
        ├── YES → git clone <repository-url>
        │
        └── NO → create project/repository
```

For an existing local repository that needs GitHub:

```text
LOCAL PROJECT
      │
      ▼
git init
      │
      ▼
git add
      │
      ▼
git commit
      │
      ▼
git remote add origin
      │
      ▼
git push -u origin main
      │
      ▼
GITHUB
```

---

# 16. Standard Repository Health Check

Before troubleshooting Git repository problems, run:

```bash
pwd
git status
git rev-parse --show-toplevel
git branch --show-current
git remote -v
```

Then, when identity or push attribution is relevant:

```bash
git config --get user.name
git config --get user.email
git log -1 --format='Author: %an <%ae>'
```

These commands establish:

```text
Where am I?
        │
        ▼
What repository am I in?
        │
        ▼
Where is its root?
        │
        ▼
What branch am I using?
        │
        ▼
What remote is configured?
        │
        ▼
What identity will new commits use?
        │
        ▼
What identity did the existing commit actually use?
```

---

# 17. Lessons Learned

## Lesson 1 — A project directory and Git repository are not inherently the same thing

A normal directory becomes a Git repository when Git initializes repository metadata in `.git`.

```bash
git init
```

---

## Lesson 2 — Git and GitHub are separate systems

Git operates locally.

GitHub hosts a remote Git repository.

A local repository must be connected to a remote explicitly.

```bash
git remote add origin <repository-url>
```

---

## Lesson 3 — `git clone` and `git init` solve different problems

Use:

```bash
git init
```

when turning an existing local project into a repository.

Use:

```bash
git clone
```

when obtaining an existing remote repository on another machine.

---

## Lesson 4 — Python virtual environments have no dependency on Git

`.venv` controls Python execution and package dependencies.

`.git` controls source history and repository metadata.

They can coexist but perform completely separate functions.

---

## Lesson 5 — Git commits contain author identity

The author's email becomes part of the commit.

This can create privacy problems when pushing to a public or private Git hosting service.

---

## Lesson 6 — Changing Git configuration does not alter history

```bash
git config user.email ...
```

changes the configuration used for subsequent commits.

Existing commits retain their original metadata.

---

## Lesson 7 — Verify the commit, not merely the configuration

This:

```bash
git config --get user.email
```

answers:

> What email will Git currently use?

This:

```bash
git log -1 --format='Author: %an <%ae>'
```

answers:

> What email is actually stored in the commit?

These are different questions.

---

## Lesson 8 — Repository diagnostics should precede repository changes

Before issuing commands such as `git init`, `git remote add`, or modifying branches, establish the current state with:

```bash
pwd
git status
git rev-parse --show-toplevel
git branch --show-current
git remote -v
```

This reduces the risk of creating nested repositories, duplicate remotes, or modifying the wrong repository.

---

# 18. Command Reference

| Command | Purpose |
|---|---|
| `pwd` | Display the current filesystem directory |
| `git init` | Initialize a Git repository in the current directory |
| `git status` | Display repository, staging, and working-tree status |
| `git rev-parse --show-toplevel` | Display the root directory of the current Git repository |
| `git branch --show-current` | Display the currently checked-out branch |
| `git branch -M main` | Rename the current branch to `main` |
| `git add .` | Stage changes under the current directory |
| `git commit -m "message"` | Create a commit from staged changes |
| `git remote -v` | Display configured remote repositories and URLs |
| `git remote add origin <URL>` | Add a remote repository named `origin` |
| `git remote remove <name>` | Remove a configured remote |
| `git push -u origin main` | Push `main` to `origin` and establish upstream tracking |
| `git push` | Push local commits to the tracked upstream branch |
| `git pull` | Retrieve and integrate changes from the tracked remote branch |
| `git clone <URL>` | Create a local copy of an existing remote repository |
| `git config --get user.name` | Display the configured Git username |
| `git config --get user.email` | Display the configured Git email |
| `git config user.email "<email>"` | Set the email for the current repository |
| `git config --global user.email "<email>"` | Set the default Git email globally |
| `git log --oneline` | Display abbreviated commit history |
| `git log -1 --format='Author: %an <%ae>'` | Display the author name and email embedded in the latest commit |
| `git commit --amend --reset-author --no-edit` | Recreate the latest commit using the current author identity while retaining its message |
| `deactivate` | Exit a Python virtual environment; unrelated to Git repository state |

---

# 19. Quick Reference — New Local Project to GitHub

```bash
cd /path/to/project

git init
git branch -M main

git status

git config user.name "Your Name"
git config user.email "<github-noreply-address>"

git add .
git commit -m "Initial commit"

git remote add origin <repository-url>

git remote -v

git push -u origin main
```

Verification:

```bash
git status
git rev-parse --show-toplevel
git branch --show-current
git remote -v
git log -1 --format='Author: %an <%ae>'
```

---

# 20. Final Result

The `locator-platform` project was successfully:

- initialized as a local Git repository;
- confirmed to have `/opt/locator-platform` as its repository root;
- configured to use the `main` branch;
- connected to its GitHub remote;
- corrected to remove a duplicate remote definition;
- configured with a GitHub private noreply commit address;
- corrected to remove the private email from the initial commit;
- successfully pushed to GitHub.

The troubleshooting exercise established the complete relationship between:

```text
FILES
  ↓
WORKING DIRECTORY
  ↓
STAGING AREA
  ↓
LOCAL COMMITS
  ↓
LOCAL REPOSITORY
  ↓
REMOTE
  ↓
GITHUB
```

This forms the baseline workflow for future Git repository creation and troubleshooting.