# AUT-001 — Redaction Techniques

**Status:** Repeatable procedure; local script checks completed. Execution on the target Linux repository must be verified by the operator.

## Synopsis

Automate removal of ticket references, business/company names, person names, account usernames, and OneNote source filenames from ACT-001.md through ACT-096.md. Preview changes, preserve originals outside the repository, apply the redactions, verify the results, and commit only reviewed files.

Use `<username>` for person/account identifiers and `[organization]` for organization names. Preserve ACT numbering, operational facts, troubleshooting steps, commands, and explicitly documented uncertainties.

## Issue/Symptoms

Runbooks exported from technical notes can retain identifiers in titles, source labels, narrative text, email addresses, profile paths, and device names. Removing only full names can leave first-name references or account aliases behind. Generic capitalization matching can incorrectly remove technical terms such as Active Directory or Windows Update.

## Environment

- Linux repository containing a `14-active-work` directory with all 96 ACT Markdown files.
- Python 3 using only the standard library; Git for reviewing and recording changes.
- Utilities: `redact_runbook_metadata.py`, `redact_runbook_users.py`, and `remove_vcts_reference.py`.
- Reviewed organization aliases and optional additional people/account aliases in private UTF-8 text files outside the repository.

These utilities process the 96 individual Markdown runbooks. Combined HTML, combined Markdown, CSV indexes, ZIP archives, screenshots, and existing Git history require separate review or regeneration.

## Investigation/Troubleshooting

1. Confirm the file count and working-tree status before starting. The utilities refuse to apply if any expected ACT file is missing or is a symbolic link.
2. Locate organization names and aliases across titles, environments, source labels, email domains, and device identifiers. Record each exact alias on its own line in the private organization list. Include abbreviated and domain/device variants when they disclose the organization.
3. Review the seeded people list in `redact_runbook_users.py`. It was derived from this specific runbook collection, including known first/last-name references and selected identifiers embedded in device names. Add missed names or usernames to a private additional-terms file. This is deterministic matching, not a universal person-name detector.
4. Preview each utility with `--diff`. A diff contains original identifiers; keep terminal captures and saved previews private.
5. Check that edits retain the meaning of the technical steps. Several people all becoming `<username>` can make delegation or account-transfer relationships ambiguous; use explanatory roles such as “delegating user” and “recipient” where needed.

## Root Cause

Source identifiers were retained during document reconstruction for traceability. Redaction requires an explicit category policy and reviewed aliases; technical prose alone does not reliably distinguish people, organizations, products, and hostnames.

## Resolution

### 1. Prepare the repository and utilities

Extract the companion automation kit to a private directory outside the repository. Set these paths for your environment:

```bash
REPO='/path/to/engineering-notes'
TOOLS='/path/to/private/redaction-tools'
PRIVATE='/path/to/private/redaction-lists'
cd "$REPO"
git status --short
python3 --version
find 14-active-work -maxdepth 1 -type f -name 'ACT-*.md' | wc -l
```

Expected count: 96. Review existing changes before proceeding; avoid concurrent edits while applying redactions.

Create the private list directory and files:

```bash
mkdir -p "$PRIVATE"
chmod 700 "$PRIVATE"
touch "$PRIVATE/organizations.txt" "$PRIVATE/additional-users.txt"
chmod 600 "$PRIVATE/organizations.txt" "$PRIVATE/additional-users.txt"
```

Populate `organizations.txt` with reviewed names and aliases, one per line. Populate `additional-users.txt` only for identifiers missing from the seeded list. Blank lines and lines beginning with `#` are ignored. An empty organization list is appropriate only after confirming company names have already been removed.

### 2. Preview all categories

```bash
python3 "$TOOLS/redact_runbook_metadata.py" 14-active-work \
  --organizations-file "$PRIVATE/organizations.txt" --diff
python3 "$TOOLS/redact_runbook_users.py" 14-active-work \
  --terms-file "$PRIVATE/additional-users.txt" --diff
python3 "$TOOLS/remove_vcts_reference.py" 14-active-work --diff
```

The metadata utility removes the ticket-reference field and replaces remaining identifiers matching the historical `T########.####` pattern. It replaces reviewed company names/aliases with `[organization]` and removes that prefix from ACT titles where applicable. Other ticket-number formats need additional matching rules.

The user utility replaces reviewed names, first/last-name references, selected embedded aliases, email addresses, Windows/Linux user-profile path segments, explicitly labelled account values, and the documented scan account with `<username>`. Broad first/last-name matches require diff review; a surname can also occur in a product or other technical label.

The source utility removes both `VCTS.one` and `Completed VCTS.one`, including the trailing separator. For example, `Source: Completed VCTS.one — page 5; page ID …` becomes `Source: page 5; page ID …`. Page order and OneNote page IDs remain for traceability. Page-ID removal was not part of this redaction policy.

### 3. Apply the reviewed edits

```bash
python3 "$TOOLS/redact_runbook_metadata.py" 14-active-work \
  --organizations-file "$PRIVATE/organizations.txt" --apply
python3 "$TOOLS/redact_runbook_users.py" 14-active-work \
  --terms-file "$PRIVATE/additional-users.txt" --apply
python3 "$TOOLS/remove_vcts_reference.py" 14-active-work --apply
```

Each utility saves changed originals to a separate temporary directory outside the repository and prints its location. Backups contain the original identifiers. Save those locations privately until verification is complete. No utility commits or pushes changes.

### 4. Review and record in Git

Complete Verification below, then stage only the runbooks:

```bash
git diff --check
git diff -- 14-active-work
git add -- 14-active-work/ACT-*.md
git diff --cached -- 14-active-work
git commit -m "Redact identifiers from ACT runbooks"
```

If newly copied runbooks are untracked, `git diff` will not display them until staged; inspect them directly and review the staged diff before committing. A commit updates the current tree; identifiers already committed remain in older Git history. No history rewrite is performed by this procedure.

## Verification

1. Confirm 96 ACT files remain and their filenames/numbering are unchanged.
2. Re-run the three preview commands after applying. Each should report zero files needing changes for its configured rules. This confirms repeat-run stability, not complete discovery of every unknown identifier.
3. Search for remaining ticket patterns, source filenames, email addresses, and every reviewed company/person alias. Review unexpected results manually.

```bash
grep -nEi '\bT[0-9]{8}\.[0-9]{4}\b|VCTS\.one|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' \
  14-active-work/ACT-*.md
grep -nF '<username>' 14-active-work/ACT-*.md
git diff --check
```

The first search should have no matches for the removed categories. The second shows replacement locations for review. Inspect examples containing possessives, email delivery, delegation, local profiles, and device aliases.

4. Confirm operational facts, required sections, commands, and evidence limits remain intact. A shared placeholder can collapse distinctions between accounts; correct unclear role relationships without restoring real names.
5. Verify the rendered Markdown. Raw `<username>` may be treated as an HTML tag by some renderers; if it disappears, display it in inline code as `<username>` or escape the angle brackets in a separate formatting pass. Review that formatting pass independently.

## Lessons/Operational Notes

- Match reviewed identifiers, not every capitalized phrase. Preserve product names and technical vocabulary unless they reveal a client identity.
- Treat domains, emails, profile folders, device names, groups, and source page titles as possible indirect identifiers. The supplied utilities cover specific patterns; they do not prove complete anonymization.
- Keep private alias lists, backups, and original-name diffs outside Git. Temporary backups persist until removed by the operator or the system; retain only as long as needed.
- This collection’s previously sanitized metadata still needs review for shortened business aliases and names embedded in device labels.
- Rebuild combined libraries and download packages from the sanitized files before publishing them. These utilities do not update those artifacts.
- If rollback is needed, restore the affected ACT files from the printed backup directories. Restore the latest pass first, then earlier passes if undoing the full workflow. Do not use a blanket Git reset that could discard unrelated edits.
- Local checks verified the original user utility against all 96 runbooks, including repeat-run stability and preservation of selected technical phrases. The source utility was checked against all 96 files. The metadata utility uses reviewed-list matching; validate its previews in the target repository.

## Command Reference

| Action | Command / option |
| --- | --- |
| Preview company/ticket changes | `python3 "$TOOLS/redact_runbook_metadata.py" 14-active-work --organizations-file "$PRIVATE/organizations.txt" --diff` |
| Preview people/account changes | `python3 "$TOOLS/redact_runbook_users.py" 14-active-work --terms-file "$PRIVATE/additional-users.txt" --diff` |
| Preview source-filename changes | `python3 "$TOOLS/remove_vcts_reference.py" 14-active-work --diff` |
| Write changes | Replace `--diff` with `--apply` after reviewing the preview. |
| Inspect tracked edits | `git diff -- 14-active-work` |
| Stage ACT files | `git add -- 14-active-work/ACT-*.md` |
| Inspect staged edits | `git diff --cached -- 14-active-work` |
| Record reviewed changes | `git commit -m "Redact identifiers from ACT runbooks"` |
