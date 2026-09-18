# SAM-002 — Group Policy SYSVOL Access Failure

## Status

**Resolved**

## Environment

- Active Directory domain: `techworks.local`
- Domain Controller 1: `TECHWORKS-DC01` — `192.168.1.51`
- Domain Controller 2: `DC-02` — `192.168.1.60`
- Test client: `TW-CL00`
- Operating environment: Windows Server / Windows 11
- Services involved:
  - Active Directory Domain Services
  - DNS
  - Kerberos
  - Netlogon
  - SYSVOL
  - SMB
  - Group Policy
  - DFS/DFSR

---

## Incident Summary

While validating the newly promoted secondary domain controller, `DC-02`,
Group Policy processing failed on domain client `TW-CL00`.

Initial testing suggested a possible domain controller replication,
SYSVOL, DNS, or client trust issue.

The final root cause was an incorrect SMB share ACL on `TECHWORKS-DC01`.

The `SYSVOL` and `NETLOGON` shares on DC01 allowed only:

    BUILTIN\Administrators    Full

As a result, normal domain computer identities could not read SYSVOL from
DC01.

When Group Policy selected DC01, policy processing failed with Windows
error 5:

    Access is denied.

---

# Symptoms

Running:

    gpupdate /force

returned:

    Computer policy could not be updated successfully.

Windows reported that it could not read:

    \\techworks.local\SYSVOL\techworks.local\Policies\
    {31B2F340-016D-11D2-945F-00C04FB984F9}\gpt.ini

Both Computer Policy and User Policy eventually failed.

---

# Investigation

## 1. Validate DC02 DNS

DC02 was configured to use DC01 for DNS:

    Get-DnsClientServerAddress -AddressFamily IPv4

Result:

    192.168.1.51

AD DNS resolution was tested:

    Resolve-DnsName techworks.local

    Resolve-DnsName _ldap._tcp.dc._msdcs.techworks.local -Type SRV

Both tests succeeded.

---

## 2. Validate DC02 Promotion

DC02 appeared in Active Directory as:

    DC-02.techworks.local
    192.168.1.60
    Global Catalog: True

DC01:

    Techworks-DC01.techworks.local
    192.168.1.51
    Global Catalog: True

---

## 3. Validate AD Replication

Command:

    repadmin /replsummary

Result:

    Source DSA          fails/total
    DC-02               0 / 5
    TECHWORKS-DC01      0 / 5

    Destination DSA     fails/total
    DC-02               0 / 5
    TECHWORKS-DC01      0 / 5

AD replication was therefore functioning in both directions.

---

## 4. Validate SYSVOL and NETLOGON on DC02

Command:

    net share

DC02 successfully published:

    NETLOGON
    SYSVOL

This demonstrated that SYSVOL initialization had completed.

---

## 5. Discover Broken Client Secure Channel

On `TW-CL00`:

    Test-ComputerSecureChannel -Verbose

Initial result:

    False

    The secure channel between the local computer and
    the domain techworks.local is broken.

The secure channel was repaired against DC02:

    Test-ComputerSecureChannel -Repair -Server DC-02 -Credential (Get-Credential)

Domain credentials were supplied.

Result:

    True

After repair:

    Test-ComputerSecureChannel -Verbose

Result:

    True

This repaired the client trust relationship but did NOT resolve the
Group Policy failure.

---

## 6. Validate SMB Connectivity

From TW-CL00:

    Test-NetConnection DC-02 -Port 445

    Test-NetConnection TECHWORKS-DC01 -Port 445

Both returned:

    TcpTestSucceeded : True

This eliminated basic TCP/SMB network connectivity as the cause.

---

## 7. Validate SYSVOL File Access

Direct SYSVOL access was tested:

    Test-Path '\\DC-02\SYSVOL'

    Test-Path '\\TECHWORKS-DC01\SYSVOL'

Interactive domain-user access succeeded.

The domain-based SYSVOL path was also tested:

    Test-Path '\\techworks.local\SYSVOL'

Result:

    True

The Default Domain Policy file was tested directly:

    Test-Path '\\techworks.local\SYSVOL\techworks.local\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\gpt.ini'

Result:

    True

This established an important distinction:

> Interactive user access to SYSVOL worked even though Group Policy
> processing continued to fail.

---

# Group Policy Event Analysis

The Group Policy Operational log was queried:

    Get-WinEvent -LogName 'Microsoft-Windows-GroupPolicy/Operational' -MaxEvents 30 |
        Where-Object {$_.LevelDisplayName -in 'Error','Warning'} |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Format-List

Event ID:

    7017

The event properties were expanded.

Results included:

    Property[1] = 5

Windows error:

    5 = Access is denied

This changed the investigation from connectivity/replication toward
authorization.

---

# SYSTEM Context Testing

Computer Group Policy executes using the machine/SYSTEM security context.

A scheduled task was therefore created to test SYSVOL access as:

    NT AUTHORITY\SYSTEM

The initial results were:

    IDENTITY: nt authority\system

    DC01 SYSVOL: False
    DC02 SYSVOL: True
    DOMAIN SYSVOL: False

This was the key diagnostic result.

The client computer identity could access SYSVOL through DC02 but not
through DC01.

---

# Validate Computer Trust Against DC01

Commands:

    nltest /sc_query:techworks.local

    nltest /sc_verify:techworks.local

Results:

    Trusted DC Name \\Techworks-DC01.techworks.local

    Trusted DC Connection Status:
    NERR_Success

    Trust Verification Status:
    NERR_Success

DC Locator also successfully selected DC01:

    nltest /dsgetdc:techworks.local /force

Result:

    DC: \\Techworks-DC01.techworks.local
    Address: \\192.168.1.51

This demonstrated that the machine trust relationship with DC01 was
healthy.

---

# Compare NTFS Permissions

The Default Domain Policy `gpt.ini` ACL was checked on both domain
controllers:

    icacls "C:\Windows\SYSVOL\sysvol\techworks.local\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\gpt.ini"

Both DCs returned equivalent NTFS permissions including:

    NT AUTHORITY\Authenticated Users:(I)(RX)
    BUILTIN\Server Operators:(I)(RX)
    BUILTIN\Administrators:(I)(F)
    NT AUTHORITY\SYSTEM:(I)(F)

Therefore the NTFS ACL was not the cause.

---

# Root Cause Discovery

SMB share permissions were compared.

Commands:

    Get-SmbShareAccess -Name SYSVOL

    Get-SmbShareAccess -Name NETLOGON

## DC01

SYSVOL:

    BUILTIN\Administrators    Allow    Full

NETLOGON:

    BUILTIN\Administrators    Allow    Full

Normal domain clients had no share-level read permission.

## DC02

SYSVOL included:

    Everyone                         Allow    Read
    BUILTIN\Administrators           Allow    Full
    NT AUTHORITY\Authenticated Users Allow    Full

NETLOGON included:

    Everyone                         Allow    Read
    BUILTIN\Administrators           Allow    Full

The difference explained why the computer/SYSTEM context could read
SYSVOL through DC02 but not DC01.

---

# Root Cause

`TECHWORKS-DC01` had incorrect SMB share permissions on its `SYSVOL` and
`NETLOGON` shares.

Although:

- AD replication worked
- DNS worked
- Kerberos worked
- Netlogon worked
- TCP 445 worked
- SYSVOL existed
- NTFS permissions were correct
- The machine secure channel was healthy

the SMB share ACL prevented normal domain clients/computer identities
from reading SYSVOL through DC01.

Because Group Policy relies on SYSVOL, policy processing failed whenever
the client attempted to retrieve policy through the affected DC.

---

# Remediation

On `TECHWORKS-DC01`:

    Grant-SmbShareAccess -Name SYSVOL `
        -AccountName 'Everyone' `
        -AccessRight Read `
        -Force

    Grant-SmbShareAccess -Name NETLOGON `
        -AccountName 'Everyone' `
        -AccessRight Read `
        -Force

Permissions were verified:

    Get-SmbShareAccess -Name SYSVOL

    Get-SmbShareAccess -Name NETLOGON

Result:

    SYSVOL
    BUILTIN\Administrators    Allow    Full
    Everyone                  Allow    Read

    NETLOGON
    BUILTIN\Administrators    Allow    Full
    Everyone                  Allow    Read

---

# Post-Remediation Validation

The SYSTEM-context test was repeated from TW-CL00.

Result:

    IDENTITY: nt authority\system

    DC01 SYSVOL: True
    DC02 SYSVOL: True
    DOMAIN SYSVOL: True

This directly demonstrated that the remediation corrected the original
authorization failure.

Final Group Policy validation:

    gpupdate /force

Result:

    Computer Policy update has completed successfully.

    User Policy update has completed successfully.

---

# Resolution

**Resolved**

Final state:

    DC01 <-> DC02 AD replication       PASS
    DC01 SYSVOL                        PASS
    DC02 SYSVOL                        PASS
    Domain SYSVOL                      PASS
    Client secure channel              PASS
    SMB TCP/445                        PASS
    SYSTEM-context SYSVOL access       PASS
    Computer Group Policy              PASS
    User Group Policy                  PASS

---

# Troubleshooting Lessons

## 1. Do not assume the error message identifies the root cause

Group Policy suggested:

- network connectivity
- DNS
- replication latency
- DFS

The actual failure was an SMB share ACL.

Each layer had to be tested independently.

## 2. SMB share permissions and NTFS permissions are separate

Successful NTFS permission checks do not prove that a client can access
the file through SMB.

Effective network access depends on both:

    SMB Share ACL
          +
    NTFS ACL

## 3. User access does not prove computer-account access

A domain user could access:

    \\techworks.local\SYSVOL

while Group Policy still failed.

Testing as `NT AUTHORITY\SYSTEM` exposed the actual problem.

## 4. Validate replication before repairing replication

`repadmin /replsummary` showed zero replication failures.

This prevented unnecessary modification of a healthy AD replication
topology.

## 5. Troubleshoot from lower layers upward

Useful sequence:

    DNS / DC discovery
           ↓
    Secure channel
           ↓
    TCP connectivity
           ↓
    SMB share availability
           ↓
    SMB share ACL
           ↓
    NTFS ACL
           ↓
    SYSTEM/machine access
           ↓
    Group Policy processing

## 6. Verify remediation at the failure layer first

After modifying DC01's share ACL, SYSVOL was retested as SYSTEM before
running `gpupdate`.

This established direct cause and effect rather than relying only on the
final application-level test.

---

# Diagnostic Commands Reference

    dcdiag

    repadmin /replsummary

    net share

    Get-ADDomainController -Filter *

    Test-ComputerSecureChannel -Verbose

    nltest /dsgetdc:techworks.local

    nltest /sc_query:techworks.local

    nltest /sc_verify:techworks.local

    Test-NetConnection <DC> -Port 445

    Test-Path '\\<DC>\SYSVOL'

    Test-Path '\\techworks.local\SYSVOL'

    Get-SmbShareAccess -Name SYSVOL

    Get-SmbShareAccess -Name NETLOGON

    icacls <path>

    gpupdate /force

---

# Cleanup

Remove the temporary SYSTEM-context diagnostic task:

    Unregister-ScheduledTask -TaskName 'SAM002-SystemTest' -Confirm:$false

Remove temporary diagnostic files:

    Remove-Item C:\Windows\Temp\SAM002-SystemTest*.txt -ErrorAction SilentlyContinue

---

# Final Takeaway

A successful TCP connection to a domain controller does not prove that
Group Policy can retrieve SYSVOL.

In this incident:

    Network connectivity worked.
    AD replication worked.
    Kerberos worked.
    SYSVOL existed.
    NTFS permissions worked.

But the SMB share ACL on one domain controller prevented the machine
identity from reading SYSVOL.

Testing the same resource under the SYSTEM security context used by
computer Group Policy was the decisive diagnostic step.