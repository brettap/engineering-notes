# SAM-003 — Active Directory Domain Controller Client Failover Testing

**Category:** SAM — General Systems Administration  
**Environment:** TechWorks Lab  
**Date:** 2026-09-16  
**Status:** Completed with remediation required  
**Primary DC:** Techworks-DC01 — 192.168.1.51  
**Secondary DC:** DC-02 — 192.168.1.60  
**Domain:** techworks.local  
**Test Clients:** TW-CL00, TW-CL01

---

## 1. Objective

Validate Active Directory client behavior when the primary domain controller,
Techworks-DC01, becomes unavailable.

The test was designed to determine whether Windows domain clients could
continue using Active Directory services through DC-02, including:

- Domain Controller discovery
- DNS
- Kerberos authentication
- LDAP
- Machine secure-channel communication
- Group Policy processing

A secondary objective was to identify infrastructure dependencies that could
prevent successful domain controller failover.

---

## 2. Environment

| System | Role | IP Address |
|---|---|---|
| Techworks-DC01 | Primary DC / DNS / PDC Emulator | 192.168.1.51 |
| DC-02 | Secondary DC / DNS | 192.168.1.60 |
| TW-CL00 | Windows 11 Domain Client | DHCP |
| TW-CL01 | Windows 11 Domain Client | 192.168.1.149 |
| Netgate | Gateway / DHCP Server | 192.168.1.1 |

Both domain controllers are members of:

    techworks.local

---

## 3. Baseline Testing — TW-CL00

Before introducing the failure, domain controller discovery was verified.

Commands:

    nltest /dsgetdc:techworks.local
    nltest /dclist:techworks.local
    ipconfig /all

TW-CL00 initially selected:

    \\Techworks-DC01.techworks.local
    192.168.1.51

The client successfully discovered both domain controllers:

    Techworks-DC01.techworks.local
    DC-02.techworks.local

TW-CL00 DNS configuration:

    Primary DNS:   192.168.1.51
    Secondary DNS: 192.168.1.60

Baseline status:

    PASS

---

## 4. Failure Injection

Techworks-DC01 was gracefully shut down from Proxmox.

No client configuration was intentionally changed before the outage.

Connectivity verification:

    ping 192.168.1.51

Result:

    Request timed out
    Destination host unreachable

DC01 was confirmed unavailable.

---

## 5. TW-CL00 Domain Controller Discovery

Forced domain controller discovery:

    nltest /dsgetdc:techworks.local /force

Result:

    DC: \\DC-02.techworks.local
    Address: \\192.168.1.60

DC-02 advertised the following capabilities:

    GC
    DS
    LDAP
    KDC
    TIMESERV
    WRITABLE
    DNS_DC
    DNS_DOMAIN
    DNS_FOREST

Result:

    PASS

TW-CL00 successfully discovered DC-02 after DC01 became unavailable.

---

## 6. DNS Testing

A normal DNS lookup was attempted:

    nslookup techworks.local

The lookup continued attempting:

    192.168.1.51

and timed out.

DC-02 was then queried explicitly:

    nslookup techworks.local 192.168.1.60

Result:

    techworks.local
        192.168.1.51
        192.168.1.60

DC-02 hostname lookup:

    nslookup DC-02.techworks.local 192.168.1.60

Result:

    DC-02.techworks.local
    192.168.1.60

PowerShell DNS verification:

    Resolve-DnsName techworks.local -Server 192.168.1.60

Result:

    192.168.1.51
    192.168.1.60

Conclusion:

DC-02 DNS was operational and authoritative AD DNS data was available.

Direct DC-02 DNS:

    PASS

Default nslookup resolver failover:

    REQUIRES FURTHER INVESTIGATION

---

## 7. Kerberos Authentication Testing

A domain user logged into TW-CL00 while DC01 remained offline.

Identity:

    whoami

Result:

    techworks\tw00

Kerberos tickets were examined:

    klist

A current Ticket Granting Ticket was present:

    Client: tw00 @ TECHWORKS.LOCAL
    Server: krbtgt/TECHWORKS.LOCAL @ TECHWORKS.LOCAL
    Kdc Called: DC-02

Additional service tickets included:

    ldap/DC-02.techworks.local
    cifs/DC-02.techworks.local
    LDAP/DC-02.techworks.local

These tickets were issued during the DC01 outage.

This demonstrates that the client was not relying solely on previously cached
Windows credentials. DC-02 was actively servicing Kerberos requests.

Result:

    PASS

---

## 8. Secure Channel Verification

From an elevated command prompt:

    nltest /sc_verify:techworks.local

Result:

    Trusted DC Name \\DC-02.techworks.local
    Trusted DC Connection Status Status = 0 0x0 NERR_Success
    Trust Verification Status = 0 0x0 NERR_Success

The TW-CL00 computer account maintained a functioning domain secure channel
through DC-02.

Result:

    PASS

---

## 9. Group Policy Failover

With DC01 still offline:

    gpupdate /force

Result:

    Computer Policy update has completed successfully.
    User Policy update has completed successfully.

This demonstrates that TW-CL00 could continue processing domain Group Policy
while DC01 was unavailable.

Result:

    PASS

---

## 10. TW-CL00 Failover Summary

    DC01
    192.168.1.51
         X
      OFFLINE
         |
         |
      TW-CL00
         |
         +--------------------> DC-02
                                192.168.1.60
                                     |
                     +---------------+---------------+
                     |               |               |
                  Kerberos          LDAP            DNS
                     PASS            PASS            PASS
                     |
                  Secure Channel
                     PASS
                     |
                  Group Policy
                     PASS

TW-CL00 successfully operated against DC-02 during the DC01 outage.

---

## 11. Second Client Test — TW-CL01

The same outage was tested against TW-CL01.

Forced domain controller discovery:

    nltest /dsgetdc:techworks.local /force

Result:

    Getting DC name failed:
    Status = 1355 0x54b ERROR_NO_SUCH_DOMAIN

Group Policy processing:

    gpupdate /force

Result:

    Updating policy...

The operation appeared to stall.

Unlike TW-CL00, TW-CL01 could not successfully discover the remaining domain
controller.

Result:

    FAIL

---

## 12. TW-CL01 DNS Investigation

DNS configuration was examined:

    Get-DnsClientServerAddress -AddressFamily IPv4

Result:

    Ethernet0
    {192.168.1.51}

Unlike TW-CL00, TW-CL01 had only DC01 configured as its DNS resolver.

Full configuration:

    Host Name:       TW-CL01
    Primary Suffix:  techworks.local
    IPv4 Address:    192.168.1.149
    DHCP Server:     192.168.1.1
    DNS Server:      192.168.1.51

The DHCP lease had supplied only:

    192.168.1.51

as the DNS server.

---

## 13. DC-02 Direct DNS Verification From TW-CL01

DC-02 was queried directly:

    nslookup techworks.local 192.168.1.60

Result:

    Server: 192.168.1.60

    techworks.local
        192.168.1.51
        192.168.1.60

This proved that:

1. TW-CL01 could reach DC-02.
2. DC-02 DNS was operational.
3. The techworks.local DNS zone was available on DC-02.
4. The failure was caused by client DNS configuration rather than failure of
   the secondary domain controller.

---

## 14. Root Cause

TW-CL01 received only the following DNS server through DHCP:

    192.168.1.51

Therefore:

    DC01 offline
          |
          X
          |
    TW-CL01 DNS
          |
          +--> 192.168.1.51 only
                     |
                     X
                  OFFLINE

Without a functioning DNS resolver, TW-CL01 could not perform normal Active
Directory DC Locator operations.

This produced:

    ERROR_NO_SUCH_DOMAIN

even though DC-02 itself remained healthy and reachable.

Root cause:

    INCOMPLETE DHCP DNS CONFIGURATION

---

## 15. Required Remediation

The DHCP configuration on the Netgate gateway should distribute both Active
Directory DNS servers to domain clients:

    DNS Server 1: 192.168.1.51
    DNS Server 2: 192.168.1.60

After correcting DHCP, client leases should be renewed and verified.

Example verification:

    ipconfig /release
    ipconfig /renew
    ipconfig /all

Expected:

    DNS Servers:
        192.168.1.51
        192.168.1.60

The failover test should then be repeated against TW-CL01 and TW-CL02.

---

## 16. Test Results

| Test | TW-CL00 | TW-CL01 |
|---|---|---|
| DC01 outage detected | PASS | PASS |
| DC-02 reachable | PASS | PASS |
| DC-02 DNS direct query | PASS | PASS |
| DC Locator failover | PASS | FAIL |
| Kerberos through DC-02 | PASS | Not tested |
| Secure channel through DC-02 | PASS | Not completed |
| Computer GPO processing | PASS | FAIL/Timeout |
| User GPO processing | PASS | FAIL/Timeout |
| Redundant DNS configured | PASS | FAIL |

---

## 17. Operational Lessons

### Lesson 1 — A second DC does not automatically provide client resiliency

Deploying multiple domain controllers is only one part of redundancy.

Clients must also be capable of discovering those domain controllers.

For Active Directory, DNS is a critical dependency.

---

### Lesson 2 — Test failure scenarios rather than assuming redundancy works

DC-02 appeared healthy before the test.

A normal health check would therefore have suggested that the environment had
domain controller redundancy.

The controlled shutdown demonstrated that client configuration could still
defeat that redundancy.

---

### Lesson 3 — Test multiple clients

TW-CL00 passed the failover test.

If testing had stopped there, the environment would have appeared fully
redundant.

Testing TW-CL01 exposed inconsistent DNS configuration.

---

### Lesson 4 — Cached logon is not sufficient evidence of AD availability

Successful Windows logon alone does not prove that a domain controller
authenticated the user because Windows may use cached domain credentials.

Kerberos provided stronger evidence.

The following output confirmed live authentication against DC-02:

    Server: krbtgt/TECHWORKS.LOCAL
    Kdc Called: DC-02

---

### Lesson 5 — Validate services independently

The test separated several components:

    Network connectivity
        ↓
    DNS
        ↓
    DC Locator
        ↓
    Kerberos
        ↓
    LDAP
        ↓
    Secure Channel
        ↓
    Group Policy

Testing each layer helped distinguish a DC failure from a DNS/client
configuration failure.

---

## 18. Follow-Up Actions

- Correct Netgate DHCP DNS options.
- Configure both DC01 and DC-02 as DNS servers for domain clients.
- Renew DHCP leases on TW-CL00, TW-CL01, and TW-CL02.
- Verify DNS server configuration on all clients.
- Repeat DC01 outage testing.
- Test TW-CL02.
- Test a user account that has never previously authenticated on a selected
  workstation.
- Investigate default Windows/nslookup DNS-server failover behavior observed
  on TW-CL00.
- Verify reverse DNS/PTR configuration for both domain controllers.
- Perform the reverse exercise later by taking DC-02 offline while DC01
  remains operational.

---

## 19. Final Assessment

SAM-003 successfully demonstrated functioning Active Directory domain
controller failover on TW-CL00.

During the same exercise, TW-CL01 failed domain controller discovery because
its DHCP configuration supplied only DC01 as a DNS resolver.

DC-02 itself remained reachable and successfully answered direct DNS queries.

The test therefore identified an infrastructure configuration defect that
would have caused some domain clients to lose access to Active Directory
services during a DC01 outage.

The immediate remediation is to correct DHCP so all domain clients receive
both Active Directory DNS servers.

---

## 20. Achievement

SAM-003 demonstrated practical experience with:

- Active Directory redundancy testing
- Controlled service failure
- Windows DC Locator
- AD-integrated DNS
- Kerberos ticket validation
- LDAP
- Windows secure channels
- Group Policy processing
- DHCP/DNS dependency troubleshooting
- Root-cause isolation
- Failover validation

The exercise demonstrated an important systems administration principle:

> Redundancy must be tested from the client's perspective, not merely verified
> from the server's perspective.