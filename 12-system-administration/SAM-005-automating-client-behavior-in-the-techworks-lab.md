# SAM-005 — Automating Client Behavior in the TechWorks Lab

## Synopsis

**Issue / Objective:**  
Establish centralized workstation configuration and remote Group Policy administration for domain-joined Windows clients in the `techworks.local` lab.

**Intended Result:**  
Use Active Directory Group Policy to centrally configure workstation behavior and establish the management prerequisites necessary for an administrator to force Group Policy updates remotely with `Invoke-GPUpdate`.

**Result:**  
Successful.

The lab demonstrated:

- Centralized workstation power configuration through Group Policy Preferences.
- Deployment of Windows Defender Firewall rules through Group Policy.
- Remote Scheduled Tasks Management over RPC.
- WMI/DCOM remote management.
- Remote Group Policy refresh using `Invoke-GPUpdate`.
- Troubleshooting of firewall, RPC, WMI, authorization, and Windows access-token dependencies.
- Independent verification that remotely initiated computer and user Group Policy processing completed successfully.

The final remote refresh successfully processed policy for:

- Computer: `TECHWORKS\TW-CL01$`
- User: `TECHWORKS\tw01`
- User: `TECHWORKS\techwork-admin`

The Group Policy Operational log recorded the remote computer refresh beginning at **3:30:28 PM on September 24, 2026**, followed by user-policy processing and successful completion of computer processing at **3:30:33 PM**.  

---

# Environment

**Domain**

```text
techworks.local
```

**Workstations OU**

```text
OU=Workstations,DC=techworks,DC=local
```

**Workstations**

```text
TW-CL00
TW-CL01
TW-CL02
```

**Domain Controllers involved**

```text
Techworks-DC01
DC-02
```

**Primary test workstation**

```text
TW-CL01
```

**Management account used during remote testing**

```text
TECHWORKS\brett
```

---

# SAM-005.1 — Configure Workstation Power Management Through GPO

## Objective

Configure a workstation power setting centrally rather than modifying each workstation manually.

A new GPO was created and linked to the **Workstations OU**:

```text
Workstations - Power Management
```

The configuration was created under:

```text
Computer Configuration
└── Preferences
    └── Control Panel Settings
        └── Power Options
```

A Windows 7-or-later Power Plan preference was configured with:

```text
Action: Update
Power Plan: Balanced
Set as active power plan: Enabled

Display timeout:
    AC / Plugged in: 20 minutes
    DC / Battery:     5 minutes
```

## Verification

On `TW-CL00`:

```powershell
powercfg /getactivescheme
```

returned the Balanced power scheme:

```text
381b4222-f694-41f0-9685-ff5bb260df2e
```

The display timeout was then queried:

```powershell
powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
```

Results:

```text
AC: 0x000004b0
DC: 0x0000012c
```

Converted from hexadecimal:

```text
0x4B0 = 1200 seconds = 20 minutes
0x12C = 300 seconds  = 5 minutes
```

The workstation therefore received the intended GPO configuration.

`gpresult` subsequently confirmed that the Power Management GPO was applied to the workstation.

---

# SAM-005.2 — Test Remote Group Policy Refresh

## Objective

Move beyond manually running:

```powershell
gpupdate /force
```

on individual clients.

The goal was to allow an administrator to initiate Group Policy processing remotely from a management system or domain controller.

The workstation inventory was first retrieved from Active Directory:

```powershell
Get-ADComputer -SearchBase "OU=Workstations,DC=techworks,DC=local" -Filter * |
Select-Object Name
```

Results:

```text
TW-CL00
TW-CL01
TW-CL02
```

A remote refresh was then attempted against `TW-CL01`:

```powershell
Invoke-GPUpdate -Computer "TW-CL01" -Force -RandomDelayInMinutes 0
```

The command failed.

The error indicated that the workstation either was unavailable or the required **Remote Scheduled Tasks Management firewall rules** were disabled.

---

# SAM-005.3 — Deploy Remote Management Firewall Rules

## Initial Diagnosis

The Remote Scheduled Tasks Management firewall rules were inspected on `TW-CL01`:

```powershell
Get-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management" |
Select-Object DisplayName, Enabled, Profile
```

The relevant Domain rules were disabled.

A dedicated firewall GPO was therefore created:

```text
GPO-Workstation-Remote-Management-Firewall
```

It was linked to:

```text
Workstations OU
```

Configuration location:

```text
Computer Configuration
└── Policies
    └── Windows Settings
        └── Security Settings
            └── Windows Defender Firewall with Advanced Security
                └── Inbound Rules
```

The predefined:

```text
Remote Scheduled Tasks Management
```

rule group was added.

The resulting rules included:

```text
Remote Scheduled Tasks Management (RPC)
Remote Scheduled Tasks Management (RPC-EPMAP)
```

Both were configured:

```text
Action: Allow
Enabled: Yes

Profiles:
    Domain:  Yes
    Private: No
    Public:  No
```

This restricted the management exposure to systems operating on a domain-authenticated network.

---

# Firewall Verification and the ActiveStore Discovery

An initial firewall query appeared to indicate that the rules remained disabled even after the GPO had been applied.

This was misleading because Windows contained both:

- Local/PersistentStore copies of the predefined rules.
- Group Policy copies of the same rules.

The effective firewall policy was therefore inspected instead:

```powershell
Get-NetFirewallRule `
    -PolicyStore ActiveStore `
    -DisplayGroup "Remote Scheduled Tasks Management" |
Select-Object DisplayName,
              Enabled,
              Profile,
              PolicyStoreSourceType,
              PolicyStoreSource
```

This revealed that the effective Group Policy rules were enabled for the Domain profile while the similarly named local rules remained disabled.

## Lesson Learned

When troubleshooting Windows Defender Firewall in a managed environment, rule names alone may not be sufficient.

Multiple policy stores can contain rules with identical or similar display names.

The following properties are particularly useful:

```text
PolicyStoreSourceType
PolicyStoreSource
```

And:

```powershell
-PolicyStore ActiveStore
```

should be used when the objective is to inspect the **effective firewall configuration**.

---

# SAM-005.4 — Troubleshoot Invoke-GPUpdate

After the Remote Scheduled Tasks firewall rules were deployed, `Invoke-GPUpdate` continued to fail.

Troubleshooting was therefore performed layer by layer instead of opening additional firewall rules indiscriminately.

## Step 1 — Verify RPC Endpoint Mapper

From `DC01`:

```powershell
Test-NetConnection TW-CL01 -Port 135
```

Result:

```text
TcpTestSucceeded : True
```

This demonstrated:

```text
DNS/name resolution                  PASS
Network path                         PASS
TCP 135                              PASS
RPC Endpoint Mapper                 PASS
```

Therefore, basic RPC connectivity was not the remaining issue.

---

# Step 2 — Verify Task Scheduler

On `TW-CL01`:

```powershell
Get-Service Schedule |
Select-Object Name, Status, StartType
```

Result:

```text
Schedule    Running    Automatic
```

The Task Scheduler service itself was operational.

---

# Step 3 — Test Remote Scheduled Task Access

From `DC01`:

```cmd
schtasks /query /s TW-CL01
```

Initially:

```text
ERROR: Access is denied.
```

This shifted the investigation away from basic network connectivity and toward authentication/authorization.

---

# Step 4 — Investigate Administrator Authorization

The administrator's current security groups were checked:

```cmd
whoami /groups | findstr /i "Domain Admins"
```

No Domain Admin membership appeared in the active logon token.

Active Directory membership was then examined:

```powershell
Get-ADUser brett -Properties MemberOf |
Select-Object -ExpandProperty MemberOf
```

The account was not initially a member of:

```text
Domain Admins
```

For this lab, `brett` was added to Domain Admins.

However, remote access continued to fail immediately after the group-membership change.

## Root Cause

Windows had created the existing logon security token **before** the account became a Domain Admin.

Adding an account to an AD security group does not retroactively reconstruct an already-running Windows logon token.

The user therefore:

1. Signed out completely.
2. Signed back in.
3. Opened an elevated administrative session.

The token was checked again:

```cmd
whoami /groups | findstr /i "Domain Admins"
```

It now showed:

```text
TECHWORKS\Domain Admins
Mandatory group
Enabled by default
Enabled group
```



Remote Task Scheduler enumeration then succeeded:

```cmd
schtasks /query /s TW-CL01
```

and returned the workstation's scheduled tasks. 

## Lesson Learned

There is an important distinction between:

```text
Active Directory group membership
```

and:

```text
Groups contained in the current Windows logon token
```

Changing group membership does not necessarily modify the token of an existing interactive session.

A full sign-out/sign-in may be required before newly assigned privileges become available.

---

# Step 5 — Verify Remote Task Creation

Remote task enumeration proved **read access**, but `Invoke-GPUpdate` needs the ability to create and execute remote scheduled tasks.

A harmless diagnostic task was therefore created:

```cmd
schtasks /create /s TW-CL01 /tn "TechWorks-GPTest" /tr "cmd.exe /c exit 0" /sc ONCE /st 23:59 /ru SYSTEM /f
```

The task was successfully created.

This established:

```text
Remote Task Scheduler connectivity    PASS
Remote task enumeration               PASS
Remote task creation                  PASS
Administrator authorization           PASS
```

The diagnostic task was subsequently removed.

---

# Step 6 — Identify the Missing WMI/DCOM Dependency

Despite successful remote task creation:

```powershell
Invoke-GPUpdate -Computer "TW-CL01" -Force -RandomDelayInMinutes 0
```

continued to fail.

This demonstrated that Remote Scheduled Tasks Management alone was insufficient.

WMI/DCOM connectivity was then tested.

A DCOM-based CIM session was created:

```powershell
$DcomSession = New-CimSession `
    -ComputerName TW-CL01 `
    -SessionOption (New-CimSessionOption -Protocol Dcom)
```

Before the WMI firewall configuration was deployed, this failed with:

```text
The RPC server is unavailable.
HRESULT 0x800706ba
```

This was an important isolation point.

At this stage:

```text
TCP 135 / RPC Endpoint Mapper          PASS
Remote Task Scheduler query            PASS
Remote Task Scheduler creation         PASS
WMI over DCOM/RPC                      FAIL
Invoke-GPUpdate                        FAIL
```

---

# Step 7 — Add WMI Firewall Rules to the Management GPO

The existing:

```text
GPO-Workstation-Remote-Management-Firewall
```

was updated.

The predefined:

```text
Windows Management Instrumentation (WMI)
```

rule group was added.

The predefined rule set included:

```text
Windows Management Instrumentation (DCOM-In)
Windows Management Instrumentation (WMI-In)
Windows Management Instrumentation (ASync-In)
```

All three were enabled and restricted to:

```text
Domain:  Yes
Private: No
Public:  No
```

This preserved the lab's principle of enabling remote administrative capabilities only on the domain-authenticated network profile.

---

# Step 8 — Solve the Group Policy Bootstrap Problem

A dependency problem now existed:

```text
Invoke-GPUpdate needed WMI
        ↓
WMI firewall configuration was delivered by GPO
        ↓
TW-CL01 needed to process the updated GPO
```

Instead of manually logging onto `TW-CL01` and executing `gpupdate`, the already-functional Remote Scheduled Tasks channel was used to bootstrap the configuration.

From `DC01`:

```cmd
schtasks /create /s TW-CL01 /tn "TechWorks-GPBootstrap" /tr "gpupdate.exe /target:computer /force" /sc ONCE /st 23:59 /ru SYSTEM /f
```

The task was then executed remotely:

```cmd
schtasks /run /s TW-CL01 /tn "TechWorks-GPBootstrap"
```

Its result was queried:

```cmd
schtasks /query /s TW-CL01 /tn "TechWorks-GPBootstrap" /v /fo LIST
```

Result:

```text
Last Run Time: 9/24/2026 3:27:51 PM
Last Result:   0
Task To Run:   gpupdate.exe /target:computer /force
Run As User:   SYSTEM
```

`Last Result: 0` confirmed successful process execution.

---

# Step 9 — Verify the Bootstrap Through the Group Policy Event Log

The Group Policy Operational log later provided stronger evidence than the scheduled-task exit code alone.

At **3:27:51 PM**, `TW-CL01` recorded:

```text
Starting manual processing of policy for computer TECHWORKS\TW-CL01$
```

The workstation successfully discovered a domain controller, downloaded policy, saved it to the local datastore, and processed the applicable client-side extensions.  

At **3:27:54 PM**, Windows recorded:

```text
Completed manual processing of policy for computer TECHWORKS\TW-CL01$
```



The bootstrap was therefore verified independently of Task Scheduler.

---

# Step 10 — Retest WMI/DCOM

After the bootstrap refresh applied the updated firewall GPO:

```powershell
$DcomSession = New-CimSession `
    -ComputerName TW-CL01 `
    -SessionOption (New-CimSessionOption -Protocol Dcom)
```

succeeded.

The remote operating system was queried:

```powershell
Get-CimInstance `
    -CimSession $DcomSession `
    -ClassName Win32_OperatingSystem |
Select-Object CSName, Caption, Version
```

Result:

```text
CSName    Caption                   Version
------    -------                   -------
TW-CL01   Microsoft Windows 11 Pro  10.0.26200
```

The WMI/DCOM management path was now functional.

---

# Step 11 — Final Invoke-GPUpdate Test

The original command was executed again:

```powershell
Invoke-GPUpdate `
    -Computer "TW-CL01" `
    -Force `
    -RandomDelayInMinutes 0
```

This time it returned without an error.

Remote Task Scheduler enumeration subsequently showed Group Policy refresh tasks including:

```text
\Microsoft\Windows\GroupPolicy\GPUpdate
    gpupdate.exe /target:computer /force

\Microsoft\Windows\GroupPolicy\GPUpdate (techwork-admin@TECHWORKS)
    gpupdate.exe /target:user /force

\Microsoft\Windows\GroupPolicy\GPUpdate (tw01@TECHWORKS)
    gpupdate.exe /target:user /force
```

This demonstrated that the remote refresh mechanism had created separate processing tasks for:

- Computer policy.
- `tw01` user policy.
- `techwork-admin` user policy.

The temporary `GPUpdate` task was no longer available when subsequently queried by exact task name, consistent with the refresh task being transient. Therefore, the Windows Group Policy Operational log was used for durable verification.

---

# Final Event Log Verification

At **3:30:28 PM**, `TW-CL01` recorded another manual computer-policy refresh:

```text
Starting manual processing of policy for computer TECHWORKS\TW-CL01$
```



At **3:30:29 PM**, Windows initiated manual Group Policy processing for:

```text
TECHWORKS\tw01
```



At **3:30:30 PM**, Windows initiated manual Group Policy processing for:

```text
TECHWORKS\techwork-admin
```



The event log subsequently recorded successful completion of user processing and, at **3:30:33 PM**, successful completion of manual computer-policy processing. 

This provided end-to-end verification of:

```text
DC01
 │
 │ Invoke-GPUpdate
 ↓
WMI / DCOM
 │
 ↓
Remote Scheduled Tasks
 │
 ├── Computer policy refresh
 │
 ├── tw01 user policy refresh
 │
 └── techwork-admin user policy refresh
 │
 ↓
Domain Controller / SYSVOL policy retrieval
 │
 ↓
Client-Side Extension processing
 │
 ↓
Successful completion recorded in
Microsoft-Windows-GroupPolicy/Operational
```

---

# Final Results

## Centralized Power Management

**PASS**

Workstation power settings were centrally configured through Group Policy Preferences.

## Remote Scheduled Tasks Firewall

**PASS**

Required RPC firewall rules were centrally deployed using Group Policy.

## Effective Firewall Policy Verification

**PASS**

`ActiveStore` inspection confirmed that Group Policy rules were active despite disabled local copies of similarly named rules.

## Remote Administrative Authorization

**PASS**

The stale logon-token issue was identified and resolved through a complete sign-out/sign-in.

## Remote Scheduled Task Query

**PASS**

## Remote Scheduled Task Creation

**PASS**

## WMI/DCOM Connectivity

**PASS**

Initially failed with:

```text
0x800706ba
The RPC server is unavailable
```

and succeeded after the WMI firewall rules were deployed and processed.

## Remote Invoke-GPUpdate

**PASS**

Computer and logged-on-user Group Policy processing was successfully initiated remotely and verified through the Group Policy Operational event log.

---

# Troubleshooting Lessons Learned

### 1. An error message may identify a dependency category rather than the exact failed component

`Invoke-GPUpdate` initially suggested that the workstation was unavailable or Remote Scheduled Tasks Management firewall rules were disabled.

The workstation was reachable, and later the Scheduled Tasks path was proven functional.

The remaining failure was WMI/DCOM.

The correct approach was therefore to test each dependency rather than continually modify the firewall based only on the top-level error.

### 2. TCP 135 is only the beginning of RPC troubleshooting

Successful:

```powershell
Test-NetConnection TW-CL01 -Port 135
```

proved connectivity to the RPC Endpoint Mapper.

It did **not** prove that every RPC-based application protocol required by the management operation was functional.

### 3. Remote query access does not prove remote create access

Successful:

```cmd
schtasks /query
```

demonstrates remote Task Scheduler access, but a separate creation test established that the account could actually create remote tasks.

### 4. WMI/DCOM and WinRM are different management transports

An initial CIM test used the default WS-Man transport and failed because WinRM was unavailable.

A DCOM CIM session was required to specifically test the WMI/DCOM path relevant to the investigation.

WinRM was **not enabled simply to make the diagnostic test succeed**.

### 5. Active Directory membership and the current logon token are different things

Adding `brett` to Domain Admins changed the directory object, but the existing Windows session continued using its original token.

A complete sign-out/sign-in generated a new token containing the new group membership.

### 6. Effective firewall policy must be distinguished from local firewall configuration

The same predefined firewall rule names existed in multiple policy stores.

`ActiveStore` plus:

```text
PolicyStoreSourceType
PolicyStoreSource
```

revealed which rules were actually controlling the workstation.

### 7. One management channel can bootstrap another

Remote Scheduled Tasks worked before WMI/DCOM.

That functioning channel was used to execute:

```text
gpupdate.exe /target:computer /force
```

remotely, allowing the workstation to receive the firewall policy necessary to enable WMI/DCOM.

This avoided manually configuring the workstation.

### 8. Verify the target of event-log evidence

A Group Policy event initially examined on `DC01` described:

```text
TECHWORKS\TECHWORKS-DC01$
```

That could not be used as evidence for `TW-CL01`.

Verification was repeated against the workstation's own Group Policy Operational log.

### 9. Process exit codes are useful, but event logs provide stronger operational evidence

The bootstrap task returned:

```text
Last Result: 0
```

which proved `gpupdate.exe` exited successfully.

The Group Policy Operational log went further by demonstrating:

```text
policy processing started
→ domain controller discovered
→ policies downloaded
→ policies saved
→ client-side extensions processed
→ policy processing completed
```

That is stronger evidence of the actual administrative outcome.

---

# Security / Production Considerations

The lab temporarily used **Domain Admins** to establish and troubleshoot administrative authorization.

That should not automatically become the normal workstation-management model.

A production-oriented design should use **least privilege**, with workstation administration delegated through an appropriate administrative/security group and only the rights necessary for the required management operations.

Similarly, the firewall rules were deliberately restricted to:

```text
Domain profile only
```

rather than:

```text
Domain + Private + Public
```

This reduces exposure when a workstation is connected to an untrusted network.

---

# Cleanup

The temporary bootstrap task should be removed after testing:

```cmd
schtasks /delete /s TW-CL01 /tn "TechWorks-GPBootstrap" /f
```

The diagnostic `TechWorks-GPTest` task should likewise not remain on the workstation.

The Microsoft-managed Group Policy scheduled tasks should **not** be manually deleted as part of this cleanup.

---

# Command Reference

## `Get-ADComputer`

```powershell
Get-ADComputer -SearchBase "OU=Workstations,DC=techworks,DC=local" -Filter * |
Select-Object Name
```

**Purpose:** Retrieves computer objects from Active Directory.

**Parameters:**

- `-SearchBase` — restricts the LDAP search to the specified OU.
- `-Filter *` — returns all matching computer objects within that search base.
- `Select-Object Name` — limits displayed output to computer names.

**Why used:**  
Verified which workstations were actually contained in the Workstations OU before attempting remote management.

---

## `gpupdate /force`

```cmd
gpupdate /force
```

**Purpose:** Forces Group Policy processing.

**Switch:**

- `/force` — reapplies policy settings even if Group Policy does not detect a change.

**Why used:**  
Used during initial GPO testing and troubleshooting.

---

## `gpupdate.exe /target:computer /force`

```cmd
gpupdate.exe /target:computer /force
```

**Purpose:** Forces only computer-side Group Policy processing.

**Parameters:**

- `/target:computer` — processes computer policy rather than both computer and user policy.
- `/force` — reapplies all applicable settings.

**Why used:**  
Executed under `SYSTEM` through the temporary remote bootstrap scheduled task to retrieve the updated firewall GPO.

---

## `gpresult`

```cmd
gpresult /r /scope computer
```

**Purpose:** Displays Resultant Set of Policy information.

**Parameters:**

- `/r` — produces summary Resultant Set of Policy information.
- `/scope computer` — displays computer-side Group Policy results.

**Why used:**  
Confirmed that the workstation was in the correct OU and that the expected GPOs were applied.

---

## `powercfg /getactivescheme`

```cmd
powercfg /getactivescheme
```

**Purpose:** Displays the currently active Windows power plan.

**Why used:**  
Verified that the expected Balanced plan was active after the Power Management GPO was processed.

---

## `powercfg /query`

```cmd
powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
```

**Purpose:** Queries settings from the active power scheme.

**Arguments:**

- `SCHEME_CURRENT` — references the active power plan.
- `SUB_VIDEO` — selects display/video power settings.
- `VIDEOIDLE` — selects the display idle timeout.

**Why used:**  
Verified the actual AC and DC display timeout values after Group Policy processing.

---

## `Get-NetFirewallRule`

Initial query:

```powershell
Get-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management" |
Select-Object DisplayName, Enabled, Profile
```

Effective-policy query:

```powershell
Get-NetFirewallRule `
    -PolicyStore ActiveStore `
    -DisplayGroup "Remote Scheduled Tasks Management" |
Select-Object DisplayName,
              Enabled,
              Profile,
              PolicyStoreSourceType,
              PolicyStoreSource
```

**Purpose:** Retrieves Windows Defender Firewall rules.

**Important parameters:**

- `-DisplayGroup` — returns rules belonging to a predefined firewall group.
- `-PolicyStore ActiveStore` — queries the effective policy assembled from applicable policy sources.

**Important output fields:**

- `Enabled` — whether the rule is enabled.
- `Profile` — network profiles to which the rule applies.
- `PolicyStoreSourceType` — identifies the type of policy source.
- `PolicyStoreSource` — identifies where the rule originated.

**Why used:**  
Distinguished effective GPO firewall rules from disabled local copies of similarly named rules.

---

## `Test-NetConnection`

```powershell
Test-NetConnection TW-CL01 -Port 135
```

**Purpose:** Tests TCP connectivity to a target system.

**Parameters:**

- `TW-CL01` — remote host.
- `-Port 135` — tests the RPC Endpoint Mapper port.

**Why used:**  
Established that DNS resolution, IP connectivity, and TCP connectivity to the RPC Endpoint Mapper were working.

---

## `Get-Service`

```powershell
Get-Service Schedule |
Select-Object Name, Status, StartType
```

**Purpose:** Retrieves Windows service status.

**Why used:**  
Verified that the Task Scheduler service on the workstation was running and configured for automatic startup.

---

## `whoami /groups`

```cmd
whoami /groups
```

Filtered form:

```cmd
whoami /groups | findstr /i "Domain Admins"
```

**Purpose:** Displays security groups contained in the current Windows access token.

**Switch / filtering:**

- `/groups` — displays token group membership.
- `findstr /i` — performs a case-insensitive text search.

**Why used:**  
Determined whether the current interactive session actually contained Domain Admin membership after the AD account was modified.

---

## `Get-ADUser`

```powershell
Get-ADUser brett -Properties MemberOf |
Select-Object -ExpandProperty MemberOf
```

**Purpose:** Retrieves an Active Directory user object and its group-membership attribute.

**Parameters:**

- `brett` — target AD account.
- `-Properties MemberOf` — requests the non-default `MemberOf` property.
- `-ExpandProperty MemberOf` — outputs the individual distinguished names rather than a formatted collection.

**Why used:**  
Compared directory-level membership with membership contained in the active Windows logon token.

---

## `schtasks /query`

```cmd
schtasks /query /s TW-CL01
```

**Purpose:** Queries Task Scheduler on a remote computer.

**Parameter:**

- `/s TW-CL01` — specifies the remote system.

**Why used:**  
Tested Remote Scheduled Tasks connectivity and authorization.

---

## `schtasks /create`

Diagnostic task:

```cmd
schtasks /create /s TW-CL01 /tn "TechWorks-GPTest" /tr "cmd.exe /c exit 0" /sc ONCE /st 23:59 /ru SYSTEM /f
```

Bootstrap task:

```cmd
schtasks /create /s TW-CL01 /tn "TechWorks-GPBootstrap" /tr "gpupdate.exe /target:computer /force" /sc ONCE /st 23:59 /ru SYSTEM /f
```

**Purpose:** Creates a scheduled task on a remote system.

**Parameters:**

- `/s TW-CL01` — remote computer.
- `/tn` — task name.
- `/tr` — command executed by the task.
- `/sc ONCE` — creates a one-time schedule.
- `/st 23:59` — provides the required start time.
- `/ru SYSTEM` — executes the task as Local System.
- `/f` — overwrites an existing task with the same name.

**Why used:**  
First proved that remote task **creation**, not merely enumeration, worked. It was then used as the bootstrap mechanism for computer Group Policy processing.

---

## `schtasks /run`

```cmd
schtasks /run /s TW-CL01 /tn "TechWorks-GPBootstrap"
```

**Purpose:** Immediately starts an existing remote scheduled task.

**Why used:**  
Executed the bootstrap Group Policy refresh without waiting for the task's scheduled time.

---

## `schtasks /query /v /fo LIST`

```cmd
schtasks /query /s TW-CL01 /tn "TechWorks-GPBootstrap" /v /fo LIST
```

**Purpose:** Retrieves detailed information about a specific remote scheduled task.

**Parameters:**

- `/tn` — identifies the task.
- `/v` — verbose output.
- `/fo LIST` — displays output as a readable list.

**Why used:**  
Verified the task's execution time, command, run-as identity, status, and `Last Result`.

---

## `schtasks /delete`

```cmd
schtasks /delete /s TW-CL01 /tn "TechWorks-GPBootstrap" /f
```

**Purpose:** Deletes a remote scheduled task.

**Parameters:**

- `/s` — remote computer.
- `/tn` — task name.
- `/f` — suppresses confirmation.

**Why used:**  
Removes the temporary bootstrap artifact after troubleshooting.

---

## `New-CimSessionOption`

```powershell
New-CimSessionOption -Protocol Dcom
```

**Purpose:** Creates CIM session options specifying DCOM rather than WS-Man.

**Parameter:**

- `-Protocol Dcom` — forces the CIM connection to use DCOM/RPC.

**Why used:**  
Allowed WMI/DCOM to be tested independently of WinRM.

---

## `New-CimSession`

```powershell
$DcomSession = New-CimSession `
    -ComputerName TW-CL01 `
    -SessionOption (New-CimSessionOption -Protocol Dcom)
```

**Purpose:** Creates a reusable CIM management session to a remote computer.

**Parameters:**

- `-ComputerName TW-CL01` — specifies the workstation.
- `-SessionOption` — supplies the DCOM transport configuration.

**Why used:**  
Directly tested whether WMI over DCOM/RPC was available.

Before the WMI firewall GPO was processed, it failed with:

```text
0x800706ba
The RPC server is unavailable
```

Afterward, it succeeded.

---

## `Get-CimInstance`

```powershell
Get-CimInstance `
    -CimSession $DcomSession `
    -ClassName Win32_OperatingSystem |
Select-Object CSName, Caption, Version
```

**Purpose:** Queries a CIM/WMI class.

**Parameters:**

- `-CimSession $DcomSession` — uses the explicitly created DCOM session.
- `-ClassName Win32_OperatingSystem` — retrieves operating-system information.

**Why used:**  
Provided an application-level verification that WMI/DCOM was functioning after the firewall GPO was applied.

---

## `Invoke-GPUpdate`

```powershell
Invoke-GPUpdate `
    -Computer "TW-CL01" `
    -Force `
    -RandomDelayInMinutes 0
```

**Purpose:** Initiates Group Policy processing remotely.

**Parameters:**

- `-Computer "TW-CL01"` — specifies the target workstation.
- `-Force` — reapplies all applicable Group Policy settings.
- `-RandomDelayInMinutes 0` — removes the randomized refresh delay.

**Why used:**  
This was the primary remote-management objective of SAM-005.

A zero-minute delay was appropriate for controlled lab testing. In larger environments, randomized delays can reduce the impact of many systems refreshing policy simultaneously.

---

## `Get-WinEvent`

```powershell
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-GroupPolicy/Operational'
    StartTime = [datetime]'2026-09-24 15:25:00'
} |
Select-Object TimeCreated, Id, LevelDisplayName, Message |
Sort-Object TimeCreated
```

**Purpose:** Retrieves Windows events using structured filtering.

**Filter values:**

- `LogName` — selects the Group Policy Operational log.
- `StartTime` — restricts results to the troubleshooting window.

**Pipeline:**

- `Select-Object` — displays the relevant event fields.
- `Sort-Object TimeCreated` — arranges events chronologically.

**Why used:**  
Provided the strongest end-to-end verification that computer and user Group Policy processing actually occurred and completed after the remote request.

---

# SAM-005 Completion State

```text
[PASS] Workstations OU targeted by GPO
[PASS] Power Management GPO deployed
[PASS] Power configuration independently verified
[PASS] Remote Scheduled Tasks firewall rules deployed
[PASS] Firewall effective policy verified
[PASS] RPC Endpoint Mapper connectivity verified
[PASS] Administrator token issue diagnosed
[PASS] Remote Task Scheduler query verified
[PASS] Remote Task Scheduler creation verified
[PASS] WMI/DCOM failure isolated
[PASS] WMI firewall rules centrally deployed
[PASS] Remote GP bootstrap completed
[PASS] WMI/DCOM connectivity verified
[PASS] Invoke-GPUpdate succeeded
[PASS] Computer policy refresh verified in event log
[PASS] Logged-on user policy refreshes verified in event log
[PASS] End-to-end remote Group Policy management operational
```

**SAM-005 status: COMPLETE.**