# GIT-002 — Git Rebase Issue and Non-Fast-Forward Push Recovery

## Purpose

Document the non-fast-forward push rejection and successful rebase recovery performed in the TechWorks `engineering-notes` repository on October 21, 2026. Explain diagnosis, verification, and safe conflict recovery for future incidents.

This document follows the procedural and command-reference conventions of [GIT-001 — New Repository Setup and Conflict Troubleshooting](GIT-001-New-repository%20conflicts-setup.md). No commits, pushes, rebases, or configuration changes were performed while creating this record.

---

## 1. Environment and Evidence

| Component | Value |
|---|---|
| Project | TechWorks engineering notes |
| Repository directory | `/home/brettcoder/dev/projects/engineering-notes` |
| Branch | `main` |
| Remote / tracking branch | `origin` / `origin/main` |
| Incident date | October 21, 2026 |
| Time zone | America/New_York; EDT, UTC−04:00 on this date |

The push rejection is reported in the incident account. Local reflogs independently confirm the rebase, replayed commits, and subsequent remote-tracking update by push. Git does not retain rejected-push terminal output in the reflog; the exact original error transcript is unavailable.

The existing [merge-conflict note](merge-conflicts.md) illustrates a conflict workflow, but does not establish that conflicts occurred in this incident. No manual conflict resolution is established by today's inspected reflog.

---

## 2. Initial Problem — Push Rejected

A push of local `main` was rejected as non-fast-forward. Representative diagnostic wording, **not a recovered terminal transcript**, is:

```text
! [rejected] main -> main (non-fast-forward)
error: failed to push some refs
```

Git refuses a normal branch update when the destination tip is not an ancestor of the proposed new tip. Here, the remote had advanced to `8d1a213` while local work continued from `6113982`. Local `main` contained two additional commits that did not yet include the remote change.

This is a history-integration problem. Retrying the same push does not integrate remote work, and force-pushing could replace history containing that work. No force push was needed for this recovery.

---

## 3. Confirmed Timeline and Commit Mapping

| Time (EDT) | Local evidence |
|---|---|
| 17:30:21 | `origin/main` advanced by fetch from `6113982` to `8d1a213` |
| 17:32:30 | Local commit `00afe14`: Adding notes on network segmentation |
| 17:36:41 | Local commit `78e266f`: Guest agent installation |
| 17:38:44 | `git pull --rebase origin main` started at `8d1a213`, replayed both local commits, and finished on `main` |
| 17:39:09 | `origin/main` updated to `4e4984a` with reflog reason `update by push` |

The integrated remote commit was `8d1a213` — `fix: normalize SAM-012 share ACL enum values`.

| Local work | Before rebase | After rebase |
|---|---|---|
| Adding notes on network segmentation | `00afe14` | `ce52563` |
| Guest agent installation | `78e266f` | `4e4984a` |

Simplified history:

```text
Before:
          8d1a213                    origin/main
         /
6113982
         \00afe14 -- 78e266f         main

After:
6113982 -- 8d1a213 -- ce52563 -- 4e4984a
                                  main, origin/main after push
```

Rebase recreated the local commits with new parents and therefore new commit IDs. The changed IDs alone do not prove that their patches were preserved correctly; review and validation remain necessary.

---

## 4. Troubleshooting and Recovery Procedure

The following is reusable syntax. The exact recovery integration command is established by the reflog; surrounding diagnostic commands are recommendations, not a reconstructed execution transcript.

### Establish Repository State

```bash
cd /home/brettcoder/dev/projects/engineering-notes
pwd
git rev-parse --show-toplevel
git branch --show-current
git status
git log --oneline --graph --decorate -12
```

Confirm the repository and `main` branch. Review staged, unstaged, and untracked files. Preserve unfinished work deliberately before rebasing; do not discard it to make the working tree clean. Avoid rebasing shared local commits without coordinating with their consumers.

### Inspect Divergence

```bash
git fetch origin
git log --oneline --left-right main...origin/main
git rev-list --left-right --count main...origin/main
```

Fetching updates remote-tracking references without integrating them into `main`. In the count output, the first number is commits unique to local `main`; the second is commits unique to `origin/main`. Both being nonzero indicates divergence. These counts describe the last fetch, not an immutable live remote state.

### Integrate Remote Work

The recorded recovery command was:

```bash
git pull --rebase origin main
```

Run from the confirmed local `main` branch with work preserved. This fetches and rebases local work onto the fetched remote branch. An explicit equivalent workflow is `git fetch origin` followed by `git rebase origin/main`; choose one integration path rather than running both unnecessarily.

If rebase completes, proceed to verification. If it pauses, follow the conflict procedure below. Do not start another pull or push during an unresolved rebase.

---

## 5. Conflict Recovery — If Rebase Pauses

This is a contingency procedure; manual conflicts were not confirmed for today's recovery.

```bash
git status
git diff --name-only --diff-filter=U
git diff
git rebase --show-current-patch
```

Inspect the stopped commit and each conflicted file. Resolve the intended content, remove conflict markers, and preserve relevant changes from both histories. For modify/delete conflicts, decide whether the file should remain or be deleted rather than blindly accepting one side. During rebase, `ours` and `theirs` can be counterintuitive: `ours` is the upstream plus commits already replayed, and `theirs` is the commit being replayed.

Stage only reviewed resolutions and continue:

```bash
git add -- path/to/resolved-file.md
git diff --cached
git diff --check
git rebase --continue
```

For a deliberately selected deletion, use `git rm -- path/to/file.md` instead of staging retained content. Repeat inspection and resolution for each stopped commit. If an editor opens, review and save the proposed commit message, then close the editor normally.

To abandon an **in-progress** rebase and return to the pre-rebase branch state:

```bash
git rebase --abort
```

Copy any valuable conflict-resolution edits elsewhere before aborting. `git rebase --skip` drops the current commit's patch; use it only after confirming that the patch is redundant or intentionally unwanted. Neither skipping nor `git reset --hard` is a general conflict fix.

If rebase has already finished, `--abort` no longer applies. Inspect `git reflog`, identify the required old tip, and preserve it under a recovery branch before planning any further history changes:

```bash
git reflog -20 --date=iso
git branch recovery/pre-rebase <verified-pre-rebase-commit>
```

The angle-bracket value is a placeholder to replace, not literal shell input. Do not reset or force-push a shared branch as an automatic follow-up.

---

## 6. Verification and Successful Outcome

After rebase, inspect the resulting history and changes:

```bash
git status
git log --oneline --graph --decorate -8
git log --oneline origin/main..main
git diff --check
```

For this incident, a targeted comparison of the original and replayed patch series is available:

```bash
git range-diff 6113982..78e266f 8d1a213..4e4984a
```

Review that comparison and run checks appropriate to the changed files before publication. A clean working tree does not prove application or documentation correctness; `git diff --check` checks pending changes and is not a full check of committed content.

After review and explicit publication authorization, a normal `git push origin main` is the reusable publication command. The historical push succeeded: the local remote-tracking reflog records `update by push` to `4e4984a` at 17:39:09 EDT. The exact historical push invocation was not retained. **No push is authorized or performed as part of writing this document.**

At inspection, before this new document was created, `git status -sb` reported `## main...origin/main` with no ahead/behind indicator and no working-tree entries. Both tips were `4e4984a`. This establishes local/tracking alignment; no fresh remote query was performed during documentation.

For future verification after an authorized push:

```bash
git status -sb
git rev-list --left-right --count main...origin/main
```

Expected local/tracking count is `0 0`. A fresh authorized fetch is needed if current server state must be checked. If another contributor advances the remote before the push, fetch, inspect, and integrate again rather than forcing the update.

---

## 7. Troubleshooting Decision Table

| Symptom | Interpretation | Next action |
|---|---|---|
| Non-fast-forward / fetch-first rejection | Destination history is not included in the proposed update | Fetch, inspect divergence, then integrate reviewed remote work |
| Local branch behind only | Remote has additional commits; no local-only commits | After preserving work, consider `git pull --ff-only origin main` |
| Both sides have unique commits | Histories diverged | Rebase unpublished local commits or use the team's approved merge workflow |
| Rebase refuses a dirty working tree | Pending changes need preservation | Inspect and preserve work; do not discard files blindly |
| Rebase reports conflicts | A replayed patch needs a content decision | Resolve, stage selected files, and `git rebase --continue` |
| Resolution is uncertain | Continuing may lose intended changes | Preserve useful edits and `git rebase --abort` while still in progress |
| Authentication or permission failure | Different problem from history divergence | Check access; do not expect rebase to repair authentication |
| Push rejected again after rebase | Remote may have advanced or another rule blocked publication | Read the actual error, fetch if appropriate, and diagnose before retrying |

---

## 8. Lessons Learned and Prevention

- Fetch and inspect remote state before beginning work and before publication, especially when editing through multiple workstations or the hosting UI.
- Rebase can preserve remote work while replaying unpublished local commits. Coordinate before rewriting commits already used by others.
- Review content after integration; a successful rebase only establishes that Git completed the operation.
- Preserve recovery evidence with `git reflog` and patch comparisons. Avoid copying credentials or credential-bearing remote URLs into documentation.
- Keep the publication decision separate from local recovery. Never force-push merely to bypass a rejection.

---

## 9. TechWorks Command Quick Reference

Commands below are reference syntax, not instructions to execute the full table. Fetch updates local references; rebase, staging, removal, and recovery-branch commands modify local state. Push publishes remotely and requires authorization.

| Command | Purpose | Quick syntax |
|---|---|---|
| `pwd` | Confirm current directory | `pwd` |
| `git rev-parse` | Confirm repository root | `git rev-parse --show-toplevel` |
| `git branch` | Confirm current branch | `git branch --show-current` |
| `git status` | Check pending changes and operation state | `git status` |
| `git fetch` | Refresh origin tracking references | `git fetch origin` |
| `git log` | Inspect divergence | `git log --oneline --left-right main...origin/main` |
| `git rev-list` | Count local-only and remote-only commits | `git rev-list --left-right --count main...origin/main` |
| `git pull --rebase` | Fetch and replay local work | `git pull --rebase origin main` |
| `git rebase` | Replay onto an already-fetched upstream | `git rebase origin/main` |
| `git pull --ff-only` | Integrate only when a fast-forward is possible | `git pull --ff-only origin main` |
| `git diff` | List unresolved files | `git diff --name-only --diff-filter=U` |
| `git rebase --show-current-patch` | Inspect the stopped commit | `git rebase --show-current-patch` |
| `git add` | Stage a reviewed conflict resolution | `git add -- path/to/resolved-file.md` |
| `git rm` | Record an intentional resolved deletion | `git rm -- path/to/file.md` |
| `git diff --cached` | Review staged resolutions | `git diff --cached` |
| `git diff --check` | Check pending patch whitespace and introduced conflict markers | `git diff --check` |
| `git rebase --continue` | Resume after resolving and staging conflicts | `git rebase --continue` |
| `git rebase --abort` | Cancel an in-progress rebase | `git rebase --abort` |
| `git rebase --skip` | Drop the current patch only when deliberately justified | `git rebase --skip` |
| `git reflog` | Locate previous local branch tips | `git reflog -20 --date=iso` |
| `git branch recovery/pre-rebase` | Preserve a verified old tip; replace placeholder | `git branch recovery/pre-rebase <verified-pre-rebase-commit>` |
| `git range-diff` | Compare today's original and replayed patch series | `git range-diff 6113982..78e266f 8d1a213..4e4984a` |
| `git push` | Publish reviewed history only when authorized | `git push origin main` |
| `git status -sb` | Verify local/tracking and working-tree state | `git status -sb` |
