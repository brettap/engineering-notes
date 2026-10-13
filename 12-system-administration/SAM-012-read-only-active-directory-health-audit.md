# SAM-012 — Read-Only Active Directory Health Audit

**Category:** SAM — General Systems Administration

**Project:** TechWorks Administration

**Domain:** `techworks.local`

**Date:** October 13, 2026

**Platform:** Windows PowerShell 5.1 / Windows Server / domain-joined management workstation

**Status:** Implementation drafted; local fixture validation performed; Windows PowerShell 5.1 and live acceptance pending

**Authorization:** Implementation only. No Windows-host collection, infrastructure changes, commits or pushes authorized in this session.

---

## Synopsis

SAM-012 collects read-only evidence for both domain controllers, evaluates health separately from evidence completeness, and writes JSON, HTML and CSV reports on the management workstation. Mandatory DC coverage remains separate from optional client coverage. An unreachable DC, missing permissions, absent machine-context evidence or an unparsed result cannot produce a healthy-and-complete conclusion.

No repair or maintenance action is included. Audit traffic can produce normal authentication, DNS and server audit events; read-only means no intentional configuration, policy, service, directory-object or infrastructure modification.

## Environment and Source Runbooks

| Logical name | Actual hostname / FQDN | Documented IPv4 address |
|---|---|---|
| DC01 | `Techworks-DC01.techworks.local` | `192.168.1.51` |
| DC02 | `DC-02.techworks.local` | `192.168.1.60` |
| Optional clients | `TW-CL00`, `TW-CL01`, `TW-CL02` | Discover from approved existing DNS; no address baseline asserted here |

These are documented targets, not newly verified live state. The audit uses a fixed DC allowlist, verifies the remote computer name, compares AD identity/address to the baseline, and discovers current forest, site, GC and PDC information. Dependent DC checks are skipped when identity cannot be verified. It does not expand its scope from discovery results.

- [SAM-002 — SYSVOL access failure](SAM-002-group-policy-sysvol-access-failure.md): share ACL, NTFS ACL, user access and machine access require distinct evidence.
- [SAM-003 — DC client failover](SAM-003-active-directory-domain-controller-client-failover-testing.md): a working secondary DNS server does not prove client resolver redundancy or failover.
- [SAM-005 — Client administration](SAM-005-automating-client-behavior-in-the-techworks-lab.md): transport and token permissions differ; event evidence must come from the assessed host.
- [SAM-011 — RDP and time synchronization](SAM-011-rdp-and-time-synchronization-issue-on-domain-controllers.md): time faults and RDP faults require separate conclusions; an open port/running service does not establish application health.
- [SAM-007.1 — Client automation troubleshooting](SAM-007.1-techworks-client-automation-troubleshooting.md): historical DNS addresses and task success do not establish current health.

## Implementation Files

- [Entry point](../10-automation/scripts/windows/Invoke-SAM012Audit.ps1)
- [Collectors, evaluators and report rendering](../10-automation/scripts/windows/SAM012Audit.psm1)
- [Local test harness](../10-automation/scripts/windows/tests/Test-SAM012Audit.ps1)
- [Synthetic fixture builder](../10-automation/scripts/windows/tests/fixtures/Healthy-SAM012.ps1)

Fixture mode is the default parameter set and requires `-FixturePath`. Network collection requires explicit `-Live` and Windows PowerShell on Windows. Tests replace the bounded collector with a throwing guard during fixture scenarios; the final job tests execute only local synthetic script blocks.

## Prerequisites and Permissions

For a separately authorized live run:

1. Use a domain-joined management workstation with Windows PowerShell 5.1. RSAT `ActiveDirectory` and `DnsClient` must already be installed. The DCs need their existing ActiveDirectory, SMB, service, registry and event query capabilities and `w32tm.exe`.
2. Confirm existing Kerberos-authenticated WinRM access to the FQDNs. The implementation uses WinRM for DC-local reads, rather than requiring RPC Event Log access. It neither enables remoting nor changes TrustedHosts, firewall rules or authentication policy.
3. Confirm direct DNS access to both documented DNS addresses and SMB access to the selected shares. Credentials/permissions are not provisioned by the script.
4. Use existing delegated rights for AD and replication reads, WinRM, service/share metadata, filesystem ACLs, Windows Time queries and requested log channels. The unconstrained default WinRM endpoint can require administrative rights. This implementation does not install a JEA endpoint; an existing constrained endpoint would require separately reviewed endpoint integration.
5. `-Credential` supplies the existing collector/remoting identity. Without it, the current authenticated identity is used. Domain Admin membership is not requested automatically. Event Log Readers alone does not provide all collector permissions.
6. `-UserReadCredential` must be an **operator-verified nonadministrative domain account**. It is used for credential-specific, temporary, nonpersistent SMB PSDrives on the management process. An existing conflicting SMB session may cause access errors; SAM-012 does not disconnect existing sessions to make a test pass.
7. Machine-account reads require independently obtained evidence from an already approved domain-client SYSTEM context. SAM-012 does not create or run tasks/services, use PsExec, or impersonate SYSTEM. Imported records are operator-supplied evidence, not cryptographic attestations.
8. Select a local report directory whose existing filesystem permissions restrict access to operational staff. Reports contain internal hostnames, identities, ACLs and event messages. No credentials, passwords or tokens are serialized. The audit does not change report-directory ACLs.

Missing prerequisites fail before collection where possible. Query authorization failures are retained per check without changing permissions.

## Mandatory DC Checks

| Check | Collection and acceptance |
|---|---|
| Identity | Remote hostname plus DC identity, address, domain, forest, root domain, site, GC and PDC. Verify the documented domain/address/GC baseline. Compare forest/PDC discovery between DCs. |
| DNS | Query each DNS server by its documented IP, independently of the workstation default resolver. Validate both host A records, the domain A records, DC LDAP/Kerberos, GC, PDC and discovered-site LDAP SRV records. Check SRV ports and resolve returned targets. Unexpected answers remain visible. |
| Replication | Read each DC's hosted naming contexts, inbound partner metadata and failure cache. Require the opposite DC as a partner for each hosted partition in this two-DC topology. Zero failures without partition coverage cannot pass. Both collectors together cover both replication directions. |
| Shares | Require SYSVOL and NETLOGON, capture share grants and NTFS SDDL, and read the Default Domain Policy `gpt.ini` with its ACL. Flag missing ordinary-client share grants and deny ACEs. Effective access is assessed separately. |
| Services | Require NTDS, DNS, Netlogon, Kdc, DFSR, LanmanServer, W32Time and EventLog to be present/running and not disabled. Capture startup mode. Report WinRM and TermService observations as management diagnostics; their running state does not prove interactive RDP health. |
| Time | Read source, status, configuration and peers with native exit codes/raw text, plus registry type/peers and time zone. Evaluate discovered forest-root PDC against the approved external-source baseline, other DCs against NT5DS. Time-zone drift is a separate warning. |
| Offset | From DC02, collect five bounded NTP offset samples against DC01. Partial/unparsed samples cannot pass. The observer is DC02, not the management workstation. |
| UserRead | Read each DC's direct SYSVOL, direct NETLOGON and the domain SYSVOL path using the supplied ordinary identity. Read the known policy file through SYSVOL. Directory objects/share existence are not substituted for successful SMB reads. |
| MachineRead | Require one fresh, correctly targeted machine-account evidence record per DC, including SYSVOL, NETLOGON and policy-file outcomes. Missing records are NOT TESTED. |
| Events | Independently query System, Directory Service, DNS Server, DFS Replication and GroupPolicy Operational on each DC. Verify enabled channels and retained time-window coverage. Event findings remain historical evidence, separate from current failure checks. |

There are **27 mandatory DC checks**, including five event channels per DC and one DC02-to-DC01 offset check. Healthy-and-complete requires every mandatory check to PASS with complete evidence. A normal run without ordinary-user credentials and external machine evidence is intentionally incomplete.

Share principal-name evaluation supports the documented English TechWorks baseline. Localized/unrecognized grants require manual review. Captured SDDL/ACLs are evidence, not a complete effective-permissions engine. AD replication checks and DFSR event/service observations do not prove complete SYSVOL content convergence.

## Optional Client Checks

`-Clients` accepts only `TW-CL00`, `TW-CL01`, `TW-CL02`; each selected client adds two optional checks:

- IPv4 DNS configuration: flag configured interfaces missing either AD resolver. Interface context is retained for operator review of VPN/secondary interfaces.
- The client's own Group Policy Operational log: retain evidence and coverage gaps without initiating policy processing.

These do not alter mandatory DC health or completeness. Optional completeness and individual client results appear separately. No selected clients means optional coverage is NOT REQUESTED. The audit does not prove DHCP configuration, machine trust repair, successful fresh authentication or outage failover.

## Parameters and Thresholds

| Parameter | Default | Meaning |
|---|---|---|
| `CheckTimeoutSeconds` | 30 | Maximum local job wait for one collector; remote connection/operation settings are also bounded |
| `EventTimeoutSeconds` | 60 | Event collector job wait |
| `OverallTimeoutSeconds` | 600 | Collection budget; remaining checks receive explicit skipped evidence |
| `ReplicationWarnMinutes` | 60 | Last replication success older than this warns; adapt to the approved topology/schedule |
| `SyncWarnMinutes` | 120 | Last successful time synchronization older than this warns |
| `OffsetWarnSeconds` | 1 | Absolute maximum sample above this warns |
| `OffsetFailSeconds` | 5 | Absolute maximum sample at or above this fails; must exceed warning threshold |
| `EventLookbackHours` | 24 | Requested event history, maximum 168 hours |
| `MaxEventsPerLog` | 200 | Event result cap; fetch one extra record to detect truncation |
| `EvidenceMaxAgeHours` | 24 | Maximum imported machine-evidence age |
| `ApprovedTimePeers` | `time.windows.com`, `time.nist.gov` | SAM-011 external-source baseline; no peer configuration is changed |
| `ExpectedTimeZone` | `Eastern Standard Time` | Presentation-zone baseline |

These are operational thresholds, not AD protocol tolerance limits. Collection is sequential, without automatic retries. Timed-out jobs are stopped and removed locally; this does not guarantee instantaneous cancellation of an in-flight server read. Cleanup and report rendering add overhead beyond the collection budget. No further collectors begin after the budget expires.

Native Windows Time status parsing supports English field labels and records the target's date culture. Unsupported language/date output, nonzero query exit codes or incomplete stripchart output produce UNKNOWN, with raw evidence retained. Server clock skew can affect event-window coverage; all reported timestamps are normalized to UTC.

## Error Handling and Evidence Completeness

Each result carries check ID, FQDN, mandatory/optional scope, observer, identity, transport, start/end UTC timestamps, findings, evidence and structured errors.

| Status | Interpretation |
|---|---|
| PASS | Collected evidence satisfies this check's criteria |
| WARN | Complete evidence identifies drift, staleness or historical events requiring review |
| FAIL | Evidence establishes failure of a defined criterion |
| UNKNOWN | Missing, invalid, inaccessible, truncated or unparsed evidence prevents a conclusion |
| NOT TESTED | Required execution context/evidence was not supplied |

A confirmed failure can coexist with incomplete evidence. `Complete` is therefore independent of `Status`. Overall mandatory health precedence is FAIL, UNKNOWN/NOT TESTED, WARN, PASS. `HealthyAndComplete` is true only when mandatory health is PASS and mandatory evidence is COMPLETE. Missing optional evidence never hides a DC failure or changes mandatory completeness.

Event filters are applied on the target. System collection selects critical/error/warning levels; other channels retain all levels within the window to include information-level Group Policy evidence. The report records channel, window, oldest retained event, truncation, provider, ID, level, source computer, record ID, UTC timestamp, message and XML. Providers plus IDs must be used when interpreting SAM-002 event 7017/error 5 and SAM-011 Time-Service event 36. A historical warning does not establish an active defect or causal link to RDP.

## Machine-Context Evidence Contract

`-MachineEvidencePath` points to a local JSON array containing one record per DC. Example **unexecuted template**:

```json
[
  {
    "Context": "Machine",
    "Identity": "TECHWORKS\\TW-CL00$",
    "Client": "TW-CL00",
    "Target": "Techworks-DC01.techworks.local",
    "TimestampUtc": "REPLACE_WITH_ACTUAL_UTC_TIMESTAMP",
    "Reads": [
      { "Resource": "SYSVOL", "Readable": true },
      { "Resource": "NETLOGON", "Readable": true },
      { "Resource": "PolicyFile", "Readable": true }
    ]
  }
]
```

Add the corresponding DC02 record. Values must describe actual reads from the stated client machine context, not administrator reads. Preserve supporting identity, actual UNC path and execution evidence with the externally obtained records. Placeholders, stale records, duplicates, wrong targets and malformed evidence cannot pass. Creating the collection mechanism is outside SAM-012.

## Operational Procedure — Separate Live Authorization Required

1. Confirm scope, existing transport/permissions, ordinary-user identity and evidence provenance.
2. Confirm thresholds against current replication schedules and time policy.
3. Start Windows PowerShell 5.1; run only after live authorization. Example invocation is documentation, not an executed action:

```powershell
$collector = Get-Credential
$ordinaryReader = Get-Credential
.\10-automation\scripts\windows\Invoke-SAM012Audit.ps1 -Live `
    -OutputDirectory C:\TechWorks\Reports\SAM-012 `
    -Credential $collector -UserReadCredential $ordinaryReader `
    -MachineEvidencePath C:\TechWorks\Evidence\machine-reads.json `
    -Clients TW-CL00,TW-CL01 -ReplicationWarnMinutes 60
```

4. Review mandatory completeness before interpreting health. Inspect per-check errors and missing execution contexts.
5. Review optional client results independently. Investigate deviations through the source runbooks; any remediation is a separately authorized change.
6. Retain reports under the existing operational access/retention policy. The implementation does not schedule itself, send reports, change permissions or delete artifacts.

## Reports

All formats use a unique `SAM-012-<RunId>` basename in the supplied local output directory. UNC, URI, provider-qualified and mapped network paths are rejected for report and evidence inputs:

- **JSON:** authoritative nested evidence, errors, parameters, UTC timestamps, mode and summaries; schema version 1.
- **HTML:** standalone summary table and expandable full JSON evidence. All dynamic evidence is HTML-escaped; no external scripts/assets.
- **CSV:** one row per check, with scope, status, completeness, identity, transport, timestamps, findings and structured error text. Detailed ACL/native/event evidence remains in JSON/HTML.

Fixture reports are explicitly marked synthetic. Existing report files are not overwritten. UNC output is rejected; use local storage. Serialization/write failures terminate visibly rather than claiming successful report creation. Partial artifacts can remain if a later format fails; retain or clean them manually under normal policy.

The entry point returns `Report` and `Paths`. Health failures are report data rather than script exceptions; callers must inspect `Report.Summary`. Setup/report failures throw. No automated infrastructure action consumes the result.

## Local Acceptance Tests

Run the dependency-free harness using PowerShell; it writes only local fixtures/reports:

```powershell
.\10-automation\scripts\windows\tests\Test-SAM012Audit.ps1 `
    -OutputDirectory C:\TechWorks\Reports\SAM-012-fixture-tests
```

The healthy fixture builder contains deterministic, synthetic data. Mutated cases exercise unreachable/wrong DC identity, SAM-002 administrator-only share grants and machine denial, user denial, missing/stale machine evidence, SAM-003 single-resolver clients, failed/missing/stale replication, SAM-011 free-running time, unsupported time output, offset thresholds/partial samples, missing SRV records, stopped services, denied permissions, truncated/wrong-host events, HTML escaping, role disagreement, malformed evidence, invalid thresholds and bounded local jobs. Fixture tests explicitly fail if live collection is attempted.

Test acceptance requires successful JSON/CSV round trips, standalone escaped HTML, separate mandatory/optional summaries and no forbidden mutating commands/switches in the module AST/source. Static review remains necessary for indirect invocation and Windows-specific query behavior; AST checks are not a security sandbox.

**Validation limit:** Linux PowerShell 7 can execute the portable evaluators/fixtures and parse PowerShell syntax. It cannot establish Windows PowerShell 5.1 execution, RSAT availability, native output behavior, existing WinRM/SMB permissions or live AD health. Run the same harness under Windows PowerShell 5.1 as the next local acceptance gate. Any real-host audit requires separate authorization; no fault injection is part of acceptance.

## Read-Only Command Boundary

Remote collectors use fixed query operations (`Get-AD*`, `Get-SmbShare*`, `Get-Acl`, `Get-Service`, `Get-WinEvent`, registry reads, DNS queries and approved `w32tm` query/stripchart switches). The only temporary management artifacts are local PowerShell jobs and credential-scoped nonpersistent PSDrives, removed in `finally` blocks.

Excluded: policy refresh, DNS registration/cache clearing, secure-channel verification that may repair state, share/NTFS changes, forced replication, time resynchronization/configuration, service actions, task creation/execution, remoting enablement, shutdown and hypervisor operations. Generic `dcdiag` DNS suites are excluded because some DNS diagnostics register test records.

### Microsoft References

- [Replication metadata query](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationpartnermetadata)
- [Windows Time query and stripchart behavior](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)
- [DNS diagnostics and dynamic test-record registration](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/troubleshoot/verify-dns-functionality-to-support-directory-replication)

## Completion State and Next Step

- Implementation and local fixture tests: review the accompanying test results and diff.
- Windows PowerShell 5.1 acceptance: pending; no Windows host contacted.
- Live health, machine-context evidence and client failover: not verified by this implementation session.
- Commit/push: not performed.

**Next Logical Step:** Review the implementation and local validation, then run the fixture harness under Windows PowerShell 5.1. Authorize real-host evidence collection separately if required.
