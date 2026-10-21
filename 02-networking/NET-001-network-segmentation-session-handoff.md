# NET-001 — TechWorks Network Segmentation and Troubleshooting

**Project:** TechWorks Administration  
**Module:** NET-001  
**Date:** October 13, 2026  
**Status:** Partially completed — IoT internet access restored; security validation pending  
**Platform:** Netgate pfSense Plus, UniFi Network, Ubuntu Docker

## ##Executive Summary

NET-001 establishes a segmented home-lab network using pfSense VLAN interfaces and UniFi switching and wireless infrastructure.

During this session, the Entertainment VLAN was observed carrying Samsung TV traffic, pfBlockerNG DNSBL behavior was investigated, and an IoT client internet connectivity failure was resolved.

**Confirmed outcome:** An Android phone connected to IoT VLAN 30 successfully accessed `https://example.com` after the intended pfSense firewall rule ordering was saved and applied.

This confirms client internet connectivity at the time of testing. It does **not** establish that inter-VLAN isolation, all DNS behaviors, or every device on the IoT network has been comprehensively tested.

**Next Logical Step:** Preserve the working configuration and test inter-VLAN isolation before declaring NET-001 complete.

## ##Network Architecture

| Component | Configuration |
|---|---|
| Firewall | Netgate 2100 running pfSense Plus |
| Management LAN | 192.168.1.0/24 |
| LAN gateway | 192.168.1.1 |
| Trusted VLAN 10 | 192.168.10.0/24 |
| Entertainment VLAN 20 | 192.168.20.0/24 |
| Entertainment gateway | 192.168.20.1 |
| IoT VLAN 30 | 192.168.30.0/24 |
| IoT gateway | 192.168.30.1 |
| Guest VLAN 40 | 192.168.40.0/24 |
| Test rack | 172.16.0.0/24 |
| Managed switch | UniFi Lite 8 PoE |
| Wireless AP | UniFi U7 Pro Max |
| UniFi controller | ubuntu-devops01, 192.168.1.114 |
| Controller deployment | Docker Compose |

### Known Clients

| Device | Network | Address |
|---|---|---|
| Samsung TV | Entertainment VLAN 20 | 192.168.20.100 |
| Android phone | IoT VLAN 30 | 192.168.30.104 |
| Wyze camera | IoT VLAN 30 | 192.168.30.105 |

Addresses are session observations, not proof of permanent DHCP reservations.

**Next Logical Step:** Export the current pfSense configuration and capture the UniFi network and port-profile settings to preserve the known working state.

## ##Entertainment VLAN 20

Samsung TV traffic was observed on VLAN 20.

The TV generated DNS and telemetry-related requests, including requests involving Samsung logging and advertising services.

Packet captures and Wireshark analysis helped establish that traffic involving `10.10.10.1` was associated with pfBlockerNG DNSBL rather than an unidentified external device.

The TV continued streaming during the observed period.

### Verification

- VLAN 20 client address observed: `192.168.20.100`.
- DNSBL-related traffic observed.
- Samsung TV streaming remained functional during the investigation.
- Complete application and service testing was not performed.

**Next Logical Step:** Review Entertainment firewall rules and verify that the TV has only the network access required for its intended services.

## ##pfBlockerNG DNSBL Investigation

pfBlockerNG DNSBL was active.

The configured IPv4 DNSBL sinkhole address was:

`10.10.10.1`

This address was associated with a pfSense LAN IP alias using a `/32` mask.

DNSBL behavior was observed for Samsung telemetry and advertising-related domains, including:

- `log-ingestion.samsungacr.com`
- `pagead2.googlesyndication.com`

The investigation established that DNSBL can redirect blocked DNS requests to a local sinkhole address rather than returning the original public destination address.

### Operational Significance

A packet capture showing traffic involving `10.10.10.1` should not automatically be interpreted as evidence of an unknown host or malicious network activity.

DNSBL logs and resolver behavior must be examined before classifying the traffic.

**Next Logical Step:** Preserve representative DNSBL log entries and packet-capture evidence, with sensitive information removed, for future troubleshooting examples.

## ##Incident — IoT Wi-Fi Connected Without Internet

**Incident ID:** NET-001-IOT-DNS-001  
**Affected network:** IoT VLAN 30  
**Affected client:** Android phone, `192.168.30.104`  
**Resolution:** Restored client internet connectivity after correcting, saving, and applying pfSense rule ordering.

### Symptoms

The phone connected to the IoT wireless network and received an address on `192.168.30.0/24`.

However, Android reported:

**Connected without internet**

With cellular data disabled, the phone initially failed to load `https://example.com`.

A Wyze camera remained accessible, but camera streaming did not establish that the phone had working general internet access.

### DNS Resolver Investigation

pfSense's DNS Resolver, Unbound, was running.

The investigation found:

- Unbound listening on TCP port 53.
- Unbound listening on UDP port 53.
- DNS Resolver network interfaces configured to All.
- `/var/unbound/access_lists.conf` included an allow entry for `192.168.30.0/24`.
- A DNS lookup of `example.com` initiated from pfSense succeeded.

The successful firewall-side lookup confirmed resolver functionality from that test context, but did not prove that the IoT phone could receive DNS responses.

### Packet Capture Investigation

The appropriate IoT VLAN interface was identified as:

`mvneta1.30`

Packet captures using host filter `192.168.30.104` showed repeated DNS requests toward:

`192.168.30.1:53`

No corresponding replies were visible in the examined capture.

An earlier capture on `mvneta0` did not provide useful evidence for the intended IoT client investigation.

This illustrates why packet captures must be performed on the interface carrying the relevant traffic.

### Firewall Rule Investigation

The intended IoT rules were arranged as follows:

| Order | Action | Source | Destination | Service |
|---|---|---|---|---|
| 1 | Pass | IoT subnets | 192.168.30.1 | TCP/UDP 53 DNS |
| 2 | Pass | Any | Any | UDP 68 → 67 DHCP |
| 3 | Block | IoT subnets | LAN subnets | IPv4 any |
| 4 | Block | IoT subnets | This Firewall (self) | IPv4 any |
| 5 | Pass | IoT subnets | Any | IPv4 any |

**Important:** The third rule was configured for LAN subnets. Its description referenced internal networks, but this did not by itself prove that all internal VLANs were blocked.

pfSense evaluates applicable interface rules in order, using the first matching rule under normal processing.

Therefore, the DNS exception must precede a broader block rule that would otherwise prevent access to the firewall's DNS service.

### Root Cause and Resolution

The intended DNS and DHCP allow rules had been moved above the blocking rules in the interface, but those changes had not been fully saved and applied.

When the rules page was revisited, the blocking rules appeared above the exceptions again.

The rules were reordered correctly, then saved and applied.

The phone subsequently reported internet access and successfully loaded `https://example.com` with cellular connectivity disabled.

**Confirmed root cause:** The intended firewall rule ordering was not active because the earlier changes had not been saved and applied.

**Confirmed resolution:** The correctly ordered rules were saved and applied, restoring the tested phone's internet connectivity.

### Lessons Learned

1. A rule shown in an editing interface is not necessarily an active rule.
2. Verify both Save and Apply Changes operations.
3. Check firewall rule ordering before modifying resolver services.
4. A firewall-side DNS lookup is not equivalent to a client-side DNS test.
5. Packet captures should use the correct VLAN interface.
6. Validate changes from the affected client rather than relying exclusively on firewall status.

**Next Logical Step:** Export the working pfSense configuration, then conduct controlled isolation tests from an IoT client without disrupting the existing management connection.

## ##UniFi Network Controller Upgrade

The UniFi Network controller is hosted on `ubuntu-devops01` using Docker Compose.

The controller was upgraded from:

`10.4.57 → 10.6.106`

Following the upgrade, the controller was accessible and the managed switch and access point were reported online.

### Backup Information

Initial upgrade backup directory:

`/home/brettcoder/unifi-backups/20261012-151707`

A later pre-upgrade MongoDB backup directory was recorded as:

`/home/brettcoder/unifi-backups/preupgrade-20261012-164000`

The initial backup archives were copied to Windows off-host storage and SHA-256 verification was reported successful.

The later MongoDB dump still requires off-host verification.

### Outstanding Configuration Maintenance

The upgrade-specific Compose file was pinned to version `10.6.106`, while the main `compose.yaml` still referenced `latest`.

This introduces a future upgrade-control concern because an image pull using `latest` can introduce a different controller version.

The main Compose file should be pinned after reviewing the running configuration and preserving backups.

No database restoration or full rollback exercise was confirmed.

**Next Logical Step:** Verify the current Docker image configuration and backup inventory, then pin the main Compose file in a separate controlled maintenance change.

## ##Security Validation Still Required

NET-001 is not fully closed from a segmentation-security perspective.

| Test | Status |
|---|---|
| IoT phone receives VLAN 30 address | Verified |
| IoT phone accesses public website | Verified |
| IoT DNS firewall exception | Configured and working in tested scenario |
| Samsung TV traffic on VLAN 20 | Observed |
| Trusted VLAN 10 client connectivity | Not verified |
| IoT → Management LAN isolation | Not verified |
| IoT → Trusted VLAN isolation | Not verified |
| IoT → Entertainment VLAN isolation | Not verified |
| Guest VLAN isolation | Not verified |
| Entertainment access policy review | Pending |
| pfSense current configuration backup | Requires confirmation |

A working internet connection must not be treated as evidence of proper segmentation.

### Recommended Test Method

Before additional firewall modifications:

1. Export the current pfSense configuration.
2. Confirm that the management workstation retains access to pfSense and UniFi.
3. Test permitted and prohibited destinations from an actual VLAN client.
4. Record client address, destination, protocol, expected result, observed result and relevant firewall logs.

Avoid disabling broad firewall rules merely to prove connectivity.

**Next Logical Step:** Conduct a controlled IoT-to-LAN isolation test, beginning with a nonessential internal test endpoint, because this directly verifies the segmentation objective without requiring a new network design.

## ##Change Log

| Date | Change or Finding | Outcome |
|---|---|---|
| October 12–13, 2026 | UniFi controller upgrade and validation | Controller 10.6.106 operational |
| October 2026 | Entertainment VLAN traffic investigation | Samsung TV traffic and DNSBL behavior observed |
| October 2026 | IoT DNS troubleshooting | DNS requests observed from phone to pfSense |
| October 13, 2026 | IoT firewall rule order saved and applied | Phone internet connectivity restored |

Exact change timestamps should be confirmed from device logs or Git history before being used in formal incident reporting.

**Next Logical Step:** Add screenshots, configuration exports and redacted packet captures as supporting evidence where available.

## ##Codex Documentation Tasks

Codex should use this document as the source of established NET-001 session facts.

Create separate Git knowledge-base documentation as appropriate for:

- NET-001 network architecture and VLAN inventory.
- NET-001 pfSense firewall and DNS troubleshooting.
- NET-001 pfBlockerNG DNSBL investigation.
- NET-001 UniFi controller upgrade and backup notes.
- NET-001 outstanding segmentation validation checklist.

Preserve the distinction between verified, observed, planned and untested states.

Do not invent screenshots, configuration exports, command outputs or test results.

Do not modify production or lab infrastructure as part of documentation generation.

Do not include passwords, tokens, private keys or other secrets.

Inspect the Git diff before committing.

**Next Logical Step:** Generate and review the individual runbooks, then commit the approved documentation to the TechWorks repository.

## ##Return to Windows Client/Server Lab

After the NET-001 documentation is committed, resume TechWorks SAM-007.

The immediate focus is Windows Active Directory client/server storage:

- Review available storage on the Proxmox mini PC.
- Decide where the SMB file server should run.
- Establish file shares and NTFS/share permissions.
- Validate domain-user access from Windows clients.
- Document configuration, access controls and recovery procedures.

NET-001 segmentation testing remains an open task and should not be recorded as fully completed.

**Next Logical Step:** Resume SAM-007 network user storage design, because the client/server lab can continue while the remaining NET-001 security tests are tracked separately.
