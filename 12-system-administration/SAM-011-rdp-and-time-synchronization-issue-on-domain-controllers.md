# SAM-011 — RDP and Time Synchronization Issue on Domain Controllers

## Synopsis

**Issue:**  
TechWorks domain controller `Techworks-DC01` became inaccessible through Remote Desktop Protocol (RDP). Network connectivity remained available, several Windows services continued responding, and PowerShell remoting through WinRM remained functional. During troubleshooting, a separate Windows Time configuration problem was discovered on DC01, which holds the PDC Emulator role.

DC01 was configured to use the Active Directory domain hierarchy (`NT5DS`) for time synchronization even though it was the PDC Emulator at the top of that hierarchy. It consequently fell back to its local clock and reported:

```text
Source: Free-running System Clock
ReferenceId: LOCL
```

DC01 was reconfigured to synchronize against external NTP servers. DC02 correctly synchronized from DC01 afterward.

Correcting time synchronization **did not restore RDP access**.

Further investigation showed successful RDP authentication and session reconnection events, but the graphical RDP connection stalled. Remote Desktop Services (`TermService`) could not be restarted, session-management utilities became unreliable, and a normal Windows reboot did not resolve the condition.

Ultimately, the VM required intervention from the Proxmox virtualization layer. Proxmox's normal VM shutdown/powerdown operation also failed with a `VM quit/powerdown failed` condition. DC01 had to be forcibly powered off, left powered down for approximately five minutes, and then restarted.

**Intended Result:**  
Restore administrative access to DC01 while determining whether the failure originated from networking, Active Directory, authentication, Windows Time, Remote Desktop Services, or the virtual machine itself.

**Final Result:**  

- Network connectivity to DC01 remained operational.
- AD DS, DNS, SMB, LDAP, WinRM, and initially RDP TCP connectivity remained available.
- Domain authentication through WinRM succeeded.
- DC02 successfully provided domain services while DC01 was being diagnosed.
- A genuine PDC Emulator time-source configuration problem was discovered and corrected.
- DC02 correctly synchronized its clock from DC01.
- Correcting time synchronization did not restore RDP.
- RDP authentication succeeded server-side but interactive session establishment failed.
- `TermService` became unable to stop normally.
- A Windows reboot did not restore normal operation.
- Proxmox could not gracefully power down the VM.
- A forced VM power-off and cold restart were ultimately required.

---

# Environment

## Active Directory Domain

```text
Domain: techworks.local
Site: Default-First-Site-Name
```

## Domain Controllers

### Techworks-DC01

```text
Hostname: Techworks-DC01
IP: 192.168.1.51
Role: Domain Controller
Global Catalog: Yes
FSMO role relevant to incident: PDC Emulator
Virtualization: Proxmox
```

### DC-02

```text
Hostname: DC-02
IP: 192.168.1.60
Role: Domain Controller
Global Catalog: Yes
Virtualization: Proxmox
```

DC02 served as the alternate administrative and domain-services platform during troubleshooting.

---

# Initial Symptoms

DC01 could no longer be accessed normally through RDP.

Attempts included domain credential formats such as:

```text
TECHWORKS\brett
brett@techworks.local
```

The Proxmox console displayed the VM and Windows appeared operational, but interactive console authentication could not be completed normally.

Basic network testing indicated that DC01 was still online.

Ping succeeded and network routing required only one hop.

This immediately suggested that the incident was not a simple VM shutdown or network-connectivity failure.

---

# Phase 1 — Verify Network and Windows Service Reachability

Testing was performed from DC02.

## RDP

```powershell
Test-NetConnection Techworks-DC01 -Port 3389
```

Result:

```text
RemoteAddress    : 192.168.1.51
RemotePort       : 3389
TcpTestSucceeded : True
```

## WinRM

```powershell
Test-NetConnection Techworks-DC01 -Port 5985
```

Result:

```text
TcpTestSucceeded : True
```

## SMB

```powershell
Test-NetConnection Techworks-DC01 -Port 445
```

Result:

```text
TcpTestSucceeded : True
```

## LDAP

```powershell
Test-NetConnection Techworks-DC01 -Port 389
```

Result:

```text
TcpTestSucceeded : True
```

### Finding

The server was reachable and multiple important Windows services were listening.

This substantially reduced the likelihood of:

- VM power failure
- General network failure
- Incorrect routing
- Complete Windows failure
- Windows Firewall blocking all management access

---

# Phase 2 — Verify Active Directory Availability

DC locator was queried from DC02.

```powershell
nltest /dsgetdc:techworks.local
```

DC02 responded as the selected domain controller:

```text
DC: \\DC-02.techworks.local
Address: \\192.168.1.60
```

Both domain controllers were then enumerated:

```powershell
nltest /dclist:techworks.local
```

Result included:

```text
Techworks-DC01.techworks.local [PDC] [DS]
DC-02.techworks.local                [DS]
```

Active Directory PowerShell was also used:

```powershell
Get-ADDomainController -Filter * |
    Select-Object HostName,IPv4Address,IsGlobalCatalog,Site
```

Both DCs were returned as Global Catalog servers.

### Finding

Active Directory still recognized both domain controllers.

DC02 was successfully servicing DC locator requests while DC01 remained partially impaired.

This demonstrated why having a second domain controller is valuable: troubleshooting could continue without depending entirely upon DC01.

---

# Phase 3 — Test PowerShell Remoting

WinRM was tested:

```powershell
Test-WSMan Techworks-DC01
```

The request succeeded.

A remote PowerShell session was then established:

```powershell
Enter-PSSession -ComputerName Techworks-DC01
```

Authentication succeeded.

Verification:

```powershell
whoami
hostname
```

Result:

```text
techworks\brett
Techworks-DC01
```

### Finding

This was a major diagnostic point.

The successful PowerShell session proved:

- DC01 was running.
- WinRM was operational.
- Domain credentials were valid.
- DC01 could authenticate `TECHWORKS\brett`.
- The failure was not a general inability to authenticate against the domain.

The investigation therefore shifted toward RDP/session management and Windows services.

---

# Phase 4 — Verify Critical DC Services

From the WinRM session:

```powershell
Get-Service TermService,WinRM,Netlogon,NTDS,DNS |
    Select-Object Name,Status,StartType
```

Result:

```text
DNS         Running
Netlogon    Running
NTDS        Running
TermService Running
WinRM       Running
```

### Finding

Core Active Directory services were operational.

Remote Desktop Services was also reporting a `Running` state even though interactive RDP access was not functioning correctly.

This became important later because a service reporting `Running` does not necessarily prove that the service is internally healthy.

---

# Phase 5 — Windows Time Warning Discovered

The System event log was inspected:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName='System'
    Level=1,2,3
    StartTime=(Get-Date).AddHours(-4)
} |
Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message |
Format-Table -Wrap
```

Windows Time generated Event ID 36.

The event stated that Windows had not synchronized the system clock for approximately 7,855 seconds because none of its configured time providers supplied a usable timestamp.

This warranted immediate investigation because DC01 held the **PDC Emulator** role.

---

# Phase 6 — Inspect Windows Time Configuration

DC01 was queried:

```powershell
w32tm /query /source
```

Result:

```text
Free-running System Clock
```

Status:

```powershell
w32tm /query /status
```

Important output:

```text
Stratum: 1
ReferenceId: LOCL
Source: Free-running System Clock
```

Configuration was then examined:

```powershell
w32tm /query /configuration
```

The important setting was:

```text
Type: NT5DS
```

### Finding

`NT5DS` instructs Windows Time to obtain synchronization through the Active Directory domain hierarchy.

That is normally appropriate for:

- Domain workstations
- Member servers
- Non-PDC domain controllers

DC01, however, held the PDC Emulator role and therefore sat at the top of the domain time hierarchy.

Without an appropriate upstream source, DC01 had fallen back to:

```text
Free-running System Clock
```

This was a legitimate domain infrastructure configuration issue.

---

# Phase 7 — Examine DC02 Time Synchronization

DC02 reported:

```powershell
w32tm /query /source
```

Result:

```text
Techworks-DC01.techworks.local
```

Status showed:

```text
Stratum: 2
ReferenceId: 192.168.1.51
Source: Techworks-DC01.techworks.local
```

### Finding

DC02 was behaving correctly.

The problem was upstream:

```text
DC01
PDC Emulator
Source: Local/free-running clock
        |
        v
DC02
Source: DC01
```

DC02 was correctly following the domain hierarchy but was inheriting time from a PDC Emulator that did not itself have a valid external time source.

---

# Phase 8 — Correct DC01 NTP Configuration

DC01 was configured with external NTP sources:

```powershell
w32tm /config /manualpeerlist:"time.windows.com,0x8 time.nist.gov,0x8" /syncfromflags:manual /reliable:yes /update
```

Windows Time was restarted:

```powershell
Restart-Service w32time
```

Rediscovery and synchronization were requested:

```powershell
w32tm /resync /rediscover
```

Verification:

```powershell
w32tm /query /source
w32tm /query /status
w32tm /query /peers
```

DC01 successfully synchronized first with NIST and subsequently selected Microsoft's time source.

Example successful state:

```text
Source: time.windows.com,0x8
Leap Indicator: 0
Last Successful Sync Time: 10/6/2026 1:55:08 PM
```

Both peers reported:

```text
State: Active
Mode: 3 (Client)
```

### Corrected Time Hierarchy

```text
External NTP
    |
    +-- time.windows.com
    |
    +-- time.nist.gov
             |
             v
       Techworks-DC01
        PDC Emulator
             |
             v
           DC02
             |
             v
      Domain Members
```

---

# Phase 9 — Correct DC02 Time Zone

DC02 was discovered to still be configured for Pacific Time.

Current configuration was checked with:

```powershell
Get-TimeZone
```

The server was changed to Eastern Time:

```powershell
Set-TimeZone -Id "Eastern Standard Time"
```

Verification:

```powershell
Get-TimeZone
Get-Date
```

Windows automatically handles the EST/EDT daylight-saving transition under this time-zone identifier.

### Important Distinction

**Time zone and time synchronization are separate concepts.**

Time zone controls how a timestamp is presented locally.

Windows Time/NTP controls the underlying synchronization of the system clock.

Changing the time zone therefore did not repair the Windows Time configuration.

---

# Phase 10 — Verify DC-to-DC Clock Offset

From DC02:

```powershell
w32tm /resync /rediscover
w32tm /query /source
w32tm /query /status
```

DC02 continued using:

```text
Techworks-DC01.techworks.local
```

Clock offset was measured:

```powershell
w32tm /stripchart /computer:Techworks-DC01 /samples:5 /dataonly
```

Observed offsets were approximately:

```text
+0.2089375s
+0.1827094s
+0.1568710s
+0.1314444s
+0.1068077s
```

### Finding

The clocks were now closely synchronized.

The Windows Time problem had been corrected.

**RDP remained unusable.**

Therefore, the investigation established that the time synchronization problem was genuine but did **not** establish that it caused the RDP failure.

---

# Phase 11 — Investigate RDP Session State

Earlier session queries had shown:

```text
SESSIONNAME    USERNAME       ID    STATE
console        Administrator   1    Active
rdp-tcp#0      brett           2    Active
```

The `brett` RDP session had existed since September 23.

This raised the possibility of a stale or hung RDP session.

RDP event logs were examined.

`RemoteConnectionManager` recorded:

```text
Remote Desktop Services: User authentication succeeded

User: brett
Domain: techworks.local
```

`LocalSessionManager` recorded:

```text
Remote Desktop Services: Session reconnection succeeded

User: TECHWORKS\brett
Session ID: 2
```

Additional events showed:

```text
Session 2 has been disconnected
```

and:

```text
WDDM graphics mode is enabled
```

### Finding

This was another major diagnostic point.

The RDP client was:

1. Reaching DC01.
2. Passing authentication.
3. Being associated with an existing session.
4. Attempting session reconnection.
5. Failing to present a usable interactive desktop.

The failure therefore existed **after basic network connectivity and authentication**.

---

# Phase 12 — Verify RDP Configuration

The RDP listener configuration was queried:

```powershell
Get-ItemProperty `
'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' |
Select-Object PortNumber,UserAuthentication,SecurityLayer,MinEncryptionLevel
```

Result:

```text
PortNumber          : 3389
UserAuthentication  : 1
SecurityLayer       : 2
MinEncryptionLevel  : 2
```

RDP enablement was also verified:

```powershell
Get-ItemProperty `
'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' |
Select-Object fDenyTSConnections
```

Result:

```text
fDenyTSConnections : 0
```

### Interpretation

- TCP 3389 was correctly configured.
- RDP was enabled.
- Network Level Authentication was enabled.
- TLS was being used.
- There was no evidence justifying disabling NLA or reducing RDP security.

---

# Phase 13 — RDP Client Timeout

RDP continued hanging at:

```text
Securing remote connection...
```

Eventually the client returned:

```text
This computer can't connect to the remote computer.

Error code: 0x108
Extended error code: 0x0
```

### Finding

The client was timing out during RDP session establishment despite TCP 3389 remaining reachable.

---

# Phase 14 — Attempt to Restart Remote Desktop Services

A targeted restart was attempted from DC02:

```powershell
Invoke-Command -ComputerName Techworks-DC01 -ScriptBlock {
    Restart-Service TermService -Force
}
```

The operation failed:

```text
Service 'Remote Desktop Services (TermService)' cannot be stopped.

Cannot stop TermService service on computer '.'
```

TCP 3389 still tested successfully:

```powershell
Test-NetConnection Techworks-DC01 -Port 3389
```

Result:

```text
TcpTestSucceeded : True
```

### Finding

This was strong evidence that the RDP subsystem was not healthy despite the service continuing to report a running/listening state.

A listening TCP socket alone does not prove that the application behind that socket can successfully complete its protocol and create a user session.

---

# Phase 15 — Remote Event Log RPC Failure

An attempt was made to retrieve RDP events directly:

```powershell
Get-WinEvent -ComputerName Techworks-DC01 `
    -LogName "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" `
    -MaxEvents 20
```

The command returned:

```text
The RPC server is unavailable
```

### Important Distinction

`Get-WinEvent -ComputerName` uses RPC-based remote Event Log functionality.

This result did not necessarily mean WinRM or the entire server had failed.

It demonstrated that another Windows remote-management path was no longer operating correctly.

---

# Phase 16 — Validate DC02 Before Restarting DC01

Before restarting DC01, DC02 was verified as capable of servicing the domain.

```powershell
Get-Service NTDS,DNS,Netlogon |
    Select-Object Name,Status
```

Result:

```text
DNS      Running
Netlogon Running
NTDS     Running
```

Domain-controller diagnostics were performed:

```powershell
dcdiag /test:Advertising /test:DNS
```

Results included:

```text
DC-02 passed test Connectivity
DC-02 passed test Advertising
DC-02 passed test DNS
techworks.local passed test DNS
```

### Finding

DC02 was operational and capable of maintaining essential Active Directory and DNS functionality while DC01 was restarted.

---

# Phase 17 — Attempt Controlled Windows Restart

DC01 was restarted remotely:

```powershell
Restart-Computer -ComputerName Techworks-DC01 -Force
```

The Windows restart did **not** restore normal RDP functionality.

At this point, normal in-guest remediation had failed.

---

# Phase 18 — Proxmox-Level Recovery

The investigation escalated to the virtualization platform.

A normal Proxmox shutdown/powerdown of DC01 was attempted.

Proxmox itself reported:

```text
VM quit/powerdown failed
```

The VM therefore could not complete a normal guest shutdown from either the Windows management path or the virtualization management path.

A forced shutdown/power-off was ultimately required.

DC01 was left completely powered off for approximately five minutes.

The VM was then powered back on.

### Final Recovery Finding

A full cold power cycle at the hypervisor level was required to recover DC01.

This suggests that the final failure state extended beyond a simple RDP credential or configuration problem.

The available evidence is consistent with a severely hung Windows/VM state involving the interactive-session or related operating-system subsystem.

The precise low-level cause was not conclusively established.

---

# Root Cause Assessment

## Confirmed Issue 1 — PDC Emulator Time Configuration

DC01 was incorrectly depending on the AD domain hierarchy (`NT5DS`) despite holding the PDC Emulator role.

This resulted in:

```text
Free-running System Clock
ReferenceId: LOCL
```

The issue was corrected by configuring external NTP peers.

### Status

**Confirmed and remediated.**

---

## Confirmed Issue 2 — RDP/Windows Session Subsystem Failure

DC01 accepted TCP connections and successfully authenticated the domain user, but interactive RDP session establishment failed.

Evidence included:

- RDP Event 1149 authentication success.
- Existing RDP Session ID 2.
- Session reconnection success events.
- RDP client hanging during `Securing remote connection`.
- Error `0x108`.
- `quser`/`qwinsta` becoming unreliable.
- `TermService` unable to stop.
- Windows restart failing to restore usable RDP.
- Proxmox graceful VM powerdown also failing.
- Recovery requiring a complete VM power-off.

### Status

**Recovered through cold VM power cycle. Exact underlying root cause not conclusively identified.**

---

# Important Causation Finding

The Windows Time issue and RDP failure occurred during the same incident, but the investigation did **not** demonstrate that the time problem caused the RDP failure.

The time hierarchy was repaired and validated before RDP recovered.

RDP remained broken after:

- external NTP synchronization was established,
- DC01 and DC02 clocks were closely synchronized,
- domain authentication succeeded,
- and DC01 was restarted through Windows.

Therefore:

> **Do not document the RDP outage as being caused by time synchronization.**

The correct conclusion is that the time configuration defect was discovered while troubleshooting a separate RDP/VM failure.

---

# Lessons Learned

## 1. Ping Does Not Prove Server Health

A server can respond to ICMP while higher-level services are partially or completely unusable.

Testing individual service ports provided much better information.

---

## 2. An Open Port Does Not Prove Application Health

TCP 3389 remained reachable even while RDP could not create a usable desktop session.

The correct troubleshooting distinction is:

```text
Network connectivity
        ↓
TCP listener
        ↓
Protocol negotiation
        ↓
Authentication
        ↓
Session creation
        ↓
Usable application
```

Each layer can succeed while the next one fails.

---

## 3. WinRM Is an Important Alternate Management Plane

PowerShell remoting provided administrative access when RDP and the Proxmox interactive console were unusable.

This allowed:

- service inspection,
- authentication verification,
- event-log analysis,
- Windows Time diagnosis,
- configuration repair,
- and remote restart attempts.

Remote administration should not depend exclusively on RDP.

---

## 4. A Second Domain Controller Provides Operational Resilience

DC02 continued:

- domain-controller discovery,
- DNS,
- Netlogon,
- AD DS,
- authentication,
- and administrative access

while DC01 was impaired.

The lab therefore demonstrated the practical value of domain-controller redundancy.

---

## 5. The PDC Emulator Requires Special Time Consideration

Ordinary domain members normally use the AD hierarchy.

The forest-root PDC Emulator should ultimately synchronize with a reliable external source.

The intended TechWorks hierarchy is:

```text
External NTP
      ↓
DC01 — PDC Emulator
      ↓
DC02
      ↓
Domain Members
```

---

## 6. Time Zone and Time Synchronization Are Different

`Set-TimeZone` controls local timestamp presentation.

`w32tm` controls Windows Time synchronization.

Changing a server from Pacific to Eastern Time does not repair NTP.

---

## 7. A Running Service Is Not Necessarily a Healthy Service

`TermService` reported:

```text
Running
```

but later could not be stopped and could not provide functional RDP sessions.

Service state should therefore be combined with functional testing.

---

## 8. Avoid Weakening Security Controls Without Evidence

NLA and TLS were not disabled simply because RDP failed.

The investigation instead collected:

- listener configuration,
- authentication events,
- session events,
- and service state.

Security controls should not be removed merely as a troubleshooting shortcut.

---

## 9. Validate Redundancy Before Restarting a Domain Controller

Before restarting DC01, DC02 was checked with:

```text
NTDS
DNS
Netlogon
dcdiag Advertising
dcdiag DNS
```

This reduced the risk of taking down the only functional domain controller.

---

## 10. Cold Power Cycling Is an Escalation, Not a First Step

The VM was forcibly powered down only after:

- network testing,
- AD testing,
- WinRM testing,
- time remediation,
- RDP diagnostics,
- service restart attempts,
- Windows restart,
- and Proxmox graceful shutdown

failed to restore normal operation.

This preserves troubleshooting evidence and minimizes unnecessary risk.

---

# Command Reference

## `Test-NetConnection`

### Purpose

Tests network connectivity to a remote host and optionally a specific TCP port.

### Syntax

```powershell
Test-NetConnection <ComputerName> -Port <PortNumber>
```

### Examples

```powershell
Test-NetConnection Techworks-DC01 -Port 3389
Test-NetConnection Techworks-DC01 -Port 5985
Test-NetConnection Techworks-DC01 -Port 445
Test-NetConnection Techworks-DC01 -Port 389
```

### Important Parameters

`-ComputerName`

Specifies the destination hostname or IP address.

`-Port`

Tests whether a specific TCP port can be reached.

### Why Used

Used to separate network/service reachability from higher-level application failures.

Ports tested:

```text
3389  RDP
5985  WinRM HTTP
445   SMB
389   LDAP
```

---

## `Test-WSMan`

### Purpose

Tests whether Windows Remote Management is responding.

### Syntax

```powershell
Test-WSMan <ComputerName>
```

### Example

```powershell
Test-WSMan Techworks-DC01
```

### Why Used

Verified that DC01's WinRM management plane remained available even though RDP was unavailable.

---

## `Enter-PSSession`

### Purpose

Creates an interactive PowerShell remoting session.

### Syntax

```powershell
Enter-PSSession -ComputerName <ComputerName>
```

### Example

```powershell
Enter-PSSession -ComputerName Techworks-DC01
```

### Why Used

Provided administrative access to DC01 without requiring RDP.

---

## `Invoke-Command`

### Purpose

Executes PowerShell commands remotely through PowerShell Remoting.

### Syntax

```powershell
Invoke-Command -ComputerName <ComputerName> -ScriptBlock {
    <commands>
}
```

### Example

```powershell
Invoke-Command -ComputerName Techworks-DC01 -ScriptBlock {
    Get-Service NTDS,DNS,Netlogon
}
```

### Why Used

Allowed DC01 to be managed from DC02 while interactive RDP access was unavailable.

---

## `whoami`

### Purpose

Displays the security identity associated with the current process.

### Syntax

```powershell
whoami
```

### Example

```text
techworks\brett
```

### Why Used

Confirmed that WinRM had authenticated the intended TechWorks domain account.

---

## `hostname`

### Purpose

Displays the local computer name.

### Syntax

```powershell
hostname
```

### Why Used

Confirmed that the remote PowerShell session was executing on DC01.

---

## `nltest /dsgetdc`

### Purpose

Uses the Windows DC Locator mechanism to locate a domain controller.

### Syntax

```cmd
nltest /dsgetdc:<domain>
```

### Example

```cmd
nltest /dsgetdc:techworks.local
```

### Why Used

Verified that DC02 could successfully service domain-controller discovery.

---

## `nltest /dclist`

### Purpose

Lists domain controllers known for a domain.

### Syntax

```cmd
nltest /dclist:<domain>
```

### Example

```cmd
nltest /dclist:techworks.local
```

### Why Used

Confirmed that both DC01 and DC02 remained registered as domain controllers and identified DC01 as the PDC.

---

## `Get-ADDomainController`

### Purpose

Retrieves Active Directory domain-controller information.

### Syntax

```powershell
Get-ADDomainController -Filter *
```

### Example

```powershell
Get-ADDomainController -Filter * |
    Select-Object HostName,IPv4Address,IsGlobalCatalog,Site
```

### Why Used

Verified DC names, addresses, Global Catalog status, and AD site membership.

---

## `Get-Service`

### Purpose

Retrieves Windows service state.

### Syntax

```powershell
Get-Service <ServiceName>
```

### Example

```powershell
Get-Service TermService,WinRM,Netlogon,NTDS,DNS |
    Select-Object Name,Status,StartType
```

### Services Examined

`TermService`

Remote Desktop Services.

`WinRM`

Windows Remote Management.

`Netlogon`

Maintains the secure channel and supports domain authentication/discovery.

`NTDS`

Active Directory Domain Services.

`DNS`

Windows DNS Server.

### Why Used

Determined which critical services remained operational during the incident.

---

## `Get-WinEvent`

### Purpose

Queries Windows event logs.

### Syntax

```powershell
Get-WinEvent -FilterHashtable @{
    LogName='<log>'
    StartTime=<datetime>
}
```

### Example

```powershell
Get-WinEvent -FilterHashtable @{
    LogName='System'
    Level=1,2,3
    StartTime=(Get-Date).AddHours(-4)
}
```

### Why Used

Discovered Windows Time Event ID 36 and examined RDP session behavior.

### Remote Consideration

```powershell
Get-WinEvent -ComputerName Techworks-DC01
```

uses the remote Event Log/RPC path.

This is different from:

```powershell
Invoke-Command -ComputerName Techworks-DC01 -ScriptBlock {
    Get-WinEvent ...
}
```

which executes `Get-WinEvent` locally on DC01 through WinRM.

---

# Windows Time Commands

## `w32tm /query /source`

### Purpose

Displays the time source currently selected by Windows Time.

### Syntax

```cmd
w32tm /query /source
```

### Problem State

```text
Free-running System Clock
```

### Healthy DC01 State

```text
time.windows.com,0x8
```

or:

```text
time.nist.gov,0x8
```

### Healthy DC02 State

```text
Techworks-DC01.techworks.local
```

---

## `w32tm /query /status`

### Purpose

Displays detailed Windows Time synchronization status.

### Syntax

```cmd
w32tm /query /status
```

### Important Fields

`Stratum`

Indicates the system's distance from the authoritative time reference.

`ReferenceId`

Identifies the current reference.

`Last Successful Sync Time`

Shows the last successful synchronization.

`Source`

Shows the current selected time source.

`Poll Interval`

Shows the current synchronization polling interval.

---

## `w32tm /query /configuration`

### Purpose

Displays Windows Time configuration.

### Syntax

```cmd
w32tm /query /configuration
```

### Important Setting

```text
Type: NT5DS
```

`NT5DS` instructs Windows to use the AD domain hierarchy.

This was inappropriate as DC01's only upstream strategy because DC01 held the PDC Emulator role.

---

## `w32tm /query /peers`

### Purpose

Displays configured NTP peers and their current state.

### Syntax

```cmd
w32tm /query /peers
```

### Why Used

Confirmed that both external peers were active after remediation.

---

## `w32tm /config`

### Purpose

Changes Windows Time configuration.

### Command Used

```cmd
w32tm /config /manualpeerlist:"time.windows.com,0x8 time.nist.gov,0x8" /syncfromflags:manual /reliable:yes /update
```

### Parameters

`/manualpeerlist`

Specifies one or more manually configured NTP peers.

`0x8`

Configures the peer for client-mode NTP communication.

`/syncfromflags:manual`

Tells W32Time to use manually configured peers.

`/reliable:yes`

Marks the computer as a reliable time source for domain clients. Appropriate here because DC01 is the PDC Emulator.

`/update`

Applies the updated configuration to Windows Time.

---

## `w32tm /resync /rediscover`

### Purpose

Forces Windows Time to rediscover available sources and attempt synchronization.

### Syntax

```cmd
w32tm /resync /rediscover
```

### Why Used

Validated that DC01 could actually communicate with and synchronize against the newly configured external NTP peers.

---

## `w32tm /stripchart`

### Purpose

Measures clock offset between two computers over multiple samples.

### Syntax

```cmd
w32tm /stripchart /computer:<ComputerName> /samples:<Number> /dataonly
```

### Example

```cmd
w32tm /stripchart /computer:Techworks-DC01 /samples:5 /dataonly
```

### Why Used

Verified that DC02 and DC01 were closely synchronized after remediation.

---

# Time Zone Commands

## `Get-TimeZone`

### Purpose

Displays the local Windows time-zone configuration.

### Syntax

```powershell
Get-TimeZone
```

---

## `Set-TimeZone`

### Purpose

Changes the Windows time zone.

### Syntax

```powershell
Set-TimeZone -Id "<Windows Time Zone ID>"
```

### Example

```powershell
Set-TimeZone -Id "Eastern Standard Time"
```

### Why Used

DC02 had remained configured for Pacific Time and needed to use the TechWorks lab's Eastern Time configuration.

---

# RDP Commands

## `quser`

### Purpose

Displays information about logged-on Remote Desktop/user sessions.

### Syntax

```cmd
quser
```

### Typical Information

```text
USERNAME
SESSIONNAME
ID
STATE
IDLE TIME
LOGON TIME
```

### Why Used

Initially identified the long-running `brett` RDP session.

The command later became unreliable during the incident.

---

## `qwinsta`

### Purpose

Displays Remote Desktop Services sessions and listeners.

### Syntax

```cmd
qwinsta
```

Remote server syntax:

```cmd
qwinsta /server:<ComputerName>
```

### Example

```cmd
qwinsta /server:Techworks-DC01
```

### Why Used

Provided information about the RDP listener, console session, and existing RDP sessions.

Like `quser`, it later became unreliable while DC01 was impaired.

---

## `logoff`

### Purpose

Terminates a specific Windows session.

### Syntax

```cmd
logoff <SessionID>
```

Remote syntax:

```cmd
logoff <SessionID> /server:<ComputerName>
```

### Example

```cmd
logoff 2 /server:Techworks-DC01
```

### Caution

Always verify the session ID before executing this command.

Logging off the wrong session can terminate another administrator's work.

---

## `mstsc`

### Purpose

Starts the Microsoft Remote Desktop Connection client.

### Syntax

```cmd
mstsc
```

Direct connection:

```cmd
mstsc /v:<ComputerName>
```

### Example

```cmd
mstsc /v:Techworks-DC01
```

---

# RDP Registry Inspection

## RDP Listener

```powershell
Get-ItemProperty `
'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' |
Select-Object PortNumber,UserAuthentication,SecurityLayer,MinEncryptionLevel
```

### Important Values

`PortNumber`

RDP listening port.

`UserAuthentication`

Controls Network Level Authentication.

`SecurityLayer`

Controls the RDP security layer.

`MinEncryptionLevel`

Specifies minimum encryption requirements.

---

## RDP Enablement

```powershell
Get-ItemProperty `
'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' |
Select-Object fDenyTSConnections
```

### Interpretation

```text
0 = RDP connections permitted
1 = RDP connections denied
```

---

# Service Restart

## `Restart-Service`

### Purpose

Stops and starts a Windows service.

### Syntax

```powershell
Restart-Service <ServiceName>
```

### Example

```powershell
Restart-Service w32time
```

Remote example:

```powershell
Invoke-Command -ComputerName Techworks-DC01 -ScriptBlock {
    Restart-Service TermService -Force
}
```

### Important Parameter

`-Force`

Attempts to restart a service even when dependent services or normal service-control restrictions may otherwise interfere.

It does not guarantee that a hung service can be stopped.

During this incident, `TermService` could not be stopped even with `-Force`.

---

# `Restart-Computer`

### Purpose

Restarts Windows locally or remotely.

### Syntax

```powershell
Restart-Computer -ComputerName <ComputerName>
```

### Example

```powershell
Restart-Computer -ComputerName Techworks-DC01 -Force
```

### Important Parameter

`-Force`

Forces the operating-system restart operation rather than waiting for normal application interaction.

### Why Used

Attempted controlled recovery of DC01 before escalating to a hypervisor-level power cycle.

---

# `dcdiag`

### Purpose

Performs diagnostic testing against Active Directory domain controllers.

### Syntax

```cmd
dcdiag
```

Specific tests:

```cmd
dcdiag /test:<TestName>
```

### Command Used

```cmd
dcdiag /test:Advertising /test:DNS
```

### `Advertising`

Checks whether the domain controller is correctly advertising its available services.

### `DNS`

Performs Active Directory DNS health tests.

### Why Used

Confirmed that DC02 could continue servicing the TechWorks domain before DC01 was restarted.

---

# `runas`

## Purpose

`runas.exe` starts a program under a different Windows user account/security context.

It is useful when the current desktop session is logged on using one account but an administrative tool needs to execute under another account.

For example, a workstation can remain logged on as a standard or local account while an administrator launches PowerShell, MMC, or another administrative application using a TechWorks domain account.

## Basic Syntax

```cmd
runas /user:<Domain\User> <Program>
```

### Domain Account Example

```cmd
runas /user:TECHWORKS\brett powershell.exe
```

Windows prompts for the password belonging to `TECHWORKS\brett`.

The newly launched PowerShell process then runs using that account's security context.

---

## Launch Group Policy Management Under Domain Credentials

```cmd
runas /user:TECHWORKS\brett "mmc.exe gpmc.msc"
```

This can be useful when the interactive Windows desktop is running under another account but Group Policy Management needs to execute using domain credentials.

---

## UPN Syntax

A domain account can also be specified using its User Principal Name when appropriate:

```cmd
runas /user:brett@techworks.local powershell.exe
```

---

## `/user`

### Purpose

Specifies the account used to start the new process.

### Syntax

```cmd
runas /user:<username> <program>
```

Examples:

```cmd
runas /user:TECHWORKS\brett powershell.exe
```

```cmd
runas /user:brett@techworks.local powershell.exe
```

---

## `/profile`

### Purpose

Loads the specified user's Windows profile.

### Syntax

```cmd
runas /profile /user:TECHWORKS\brett powershell.exe
```

`/profile` is the default behavior.

Use it when the application requires settings, environment information, certificates, or other resources associated with the target user's profile.

---

## `/noprofile`

### Purpose

Starts the program without loading the target user's profile.

### Syntax

```cmd
runas /noprofile /user:TECHWORKS\brett powershell.exe
```

### Use Case

Can reduce startup time when the target application does not require the alternate user's profile.

Some applications may not behave correctly if they depend on profile-specific configuration.

---

## `/netonly`

### Purpose

Uses the supplied credentials for **remote network authentication only** while the process continues to run locally under the current user's local security context.

### Syntax

```cmd
runas /netonly /user:TECHWORKS\brett powershell.exe
```

### Use Case

Useful when accessing remote domain resources from a computer or account that does not have the desired domain identity locally.

For example:

```cmd
runas /netonly /user:TECHWORKS\brett powershell.exe
```

The new PowerShell process can then attempt access to remote resources using the supplied TechWorks credentials.

### Important Distinction

`/netonly` does **not** make the local process fully execute as the supplied account.

The alternate credentials are used when authenticating to remote network resources.

This difference is important when troubleshooting permissions.

---

## `/savecred`

### Purpose

Allows Windows to reuse credentials previously saved for the specified account.

Example syntax:

```cmd
runas /savecred /user:TECHWORKS\brett powershell.exe
```

### Security Warning

Avoid using `/savecred` casually with privileged administrative accounts.

Saved credentials can create unnecessary credential-exposure and privilege-escalation opportunities, particularly on shared or less-trusted workstations.

For TechWorks administrative practice, explicitly entering privileged credentials is preferable unless there is a deliberate and documented reason to store them.

---

## What `runas` Does Not Do

`runas` is not a replacement for:

```text
RDP
PowerShell Remoting
WinRM
Remote Server Administration Tools
Just Enough Administration
Privileged Access Workstations
```

`runas` changes the security context used by a **process**.

RDP creates an interactive remote Windows session.

PowerShell Remoting executes commands on another computer through WinRM.

These solve different administrative problems.

---

## Verify the New Security Context

After launching:

```cmd
runas /user:TECHWORKS\brett powershell.exe
```

verify the new process with:

```powershell
whoami
```

Expected:

```text
techworks\brett
```

This is an important habit:

> Do not assume a credential/context change worked. Verify the resulting security identity.

---

# Recommended Post-Incident Checks

After recovery of DC01:

```powershell
dcdiag /test:Advertising /test:DNS
```

Then:

```powershell
repadmin /replsummary
```

Verify Windows Time:

```powershell
w32tm /query /source
w32tm /query /status
```

Verify DC02:

```powershell
w32tm /query /source
```

Expected hierarchy:

```text
External NTP
      ↓
Techworks-DC01
      ↓
DC-02
      ↓
Domain Members
```

Finally verify management paths independently:

```powershell
Test-NetConnection Techworks-DC01 -Port 3389
Test-WSMan Techworks-DC01
```

and perform an actual RDP login.

---

# Problems Encountered

1. DC01 became inaccessible through RDP.
2. Proxmox console interaction was unusable.
3. DC01 was found using a free-running local clock.
4. PDC Emulator was configured for `NT5DS` instead of an appropriate external upstream time source.
5. DC02 had an incorrect Pacific time-zone configuration.
6. RDP remained broken after time synchronization was repaired.
7. A stale/long-running RDP session was discovered.
8. RDP authentication succeeded but interactive session establishment failed.
9. `quser` and `qwinsta` became unreliable.
10. `TermService` could not be stopped.
11. Remote Event Log access returned an RPC error.
12. A Windows restart did not restore RDP.
13. Proxmox graceful VM shutdown/powerdown failed.
14. A forced cold power cycle was ultimately required.

---

# Achievements

- Diagnosed DC01 without immediately rebooting it.
- Used DC02 as an alternate administrative platform.
- Demonstrated functioning domain-controller redundancy.
- Verified AD DS, DNS, LDAP, SMB, RDP, and WinRM independently.
- Used PowerShell Remoting when RDP was unavailable.
- Identified and corrected a PDC Emulator Windows Time configuration problem.
- Established external NTP synchronization for DC01.
- Verified DC02's correct downstream synchronization.
- Corrected DC02's time zone.
- Measured actual DC clock offset.
- Used RDP operational logs to distinguish authentication from session-establishment failure.
- Preserved NLA/TLS instead of weakening security controls during troubleshooting.
- Validated DC02 before restarting DC01.
- Escalated from service-level recovery to OS restart and finally hypervisor recovery in a controlled manner.

---

# Final Lesson

This incident demonstrated an important systems-administration principle:

> **Reachability, authentication, service state, and application functionality are separate layers and must be tested separately.**

DC01 could:

- respond to ping,
- accept TCP connections,
- answer LDAP,
- authenticate a domain account,
- accept WinRM,
- and report `TermService` as running,

while still being incapable of providing a usable Remote Desktop session.

It also demonstrated why redundant domain controllers and multiple administrative access methods are important.

Finally, troubleshooting uncovered a genuine Windows Time design problem that was worth correcting even though it ultimately did not explain the RDP outage.

The correct troubleshooting objective is not merely to make a system work again. It is to determine **what has actually been proven, what has been ruled out, and what remains unknown**.