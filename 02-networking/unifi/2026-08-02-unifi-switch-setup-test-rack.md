First, congratulations. I know this felt like it took forever, but from an engineering standpoint, **this was an extremely valuable lab**.

The topology screenshot tells me the story:

* ✅ Your production **USW-Lite-8-PoE** is online.
* ✅ Your **Test Rack USW-Lite-8-PoE** is online.
* ✅ Your **Test Rack U6+** is online beneath it.
* ✅ The AP is serving at least one client (your TestBench at **-35 dBm**, which is an excellent signal).

That is exactly what we wanted to accomplish.

---

# Engineering Lab Journal

## Session: UniFi Test Rack Commissioning & Adoption Troubleshooting

### Objective

Commission the portable 4TechWorks UniFi test rack consisting of:

* UniFi Lite 8 PoE
* UniFi U6+
* Existing Docker-hosted UniFi Network Application

---

## Initial Symptoms

Observed:

* Switch discovered by controller
* Adoption remained in **Adopting**
* Eventually changed to **Connection Interrupted**
* AP adopted normally
* Switch repeatedly failed despite factory resets

---

## Investigation Performed

### Layer 1

Verified:

* Ethernet link
* PoE delivery
* DHCP lease
* ICMP reachability

Result:

> Hardware healthy.

---

### Layer 2

Verified switch received:

```
192.168.1.139
```

Ping successful.

SSH successful.

---

### Device Diagnostics

SSH:

```bash
info
```

Initial output:

```
Status:
Timeout (http://172.21.0.3:8080/inform)
```

Later:

```
Unable to resolve
(http://unifi:8080/inform)
```

Key observation:

Controller was advertising an unreachable Inform Host.

---

### Controller Verification

Verified:

```
docker ps
```

Ports:

* 8080
* 8443
* 3478
* 10001

published correctly.

---

Verified:

```bash
ss -lntp
```

confirmed:

```
0.0.0.0:8080
0.0.0.0:8443
```

---

Verified:

```bash
curl -I http://192.168.1.114:8080/inform
```

Returned:

```
HTTP 400
```

Expected.

This confirmed:

* Inform service reachable
* Controller healthy

---

### Controller Configuration

Reviewed:

```
system.properties
```

Confirmed:

```
# system_ip=a.b.c.d
```

No explicit controller IP configured.

---

### Docker Investigation

Confirmed controller running on Docker bridge network.

Container hostname differed from LAN address.

---

## Resolution

Executed:

```bash
set-inform http://192.168.1.114:8080/inform
```

Controller immediately progressed through:

```
Adopting
↓

Updating
↓

Getting Ready
↓

Online
```

Final topology correctly displayed:

```
Production Switch
      │
      └── Test Rack Switch
                │
                └── U6+
                       │
                       Client
```

Commission successful.

---

# Root Cause

Not hardware.

Not PoE.

Not DHCP.

Not firmware.

Root cause:

> Docker-hosted UniFi controller advertised an unreachable Inform Host during provisioning.

---

# Lessons Learned

### Always verify:

```
info
```

before resetting hardware.

---

### Verify:

```
Status:
Timeout
Unable to resolve
Server Reject
```

These messages often identify controller configuration issues.

---

### Verify controller

```
docker ps

ss -lntp

curl
```

before suspecting the switch.

---

### `set-inform`

is a troubleshooting tool—not the permanent fix—but it can re-establish communication when the device is pointing at an incorrect inform address.

---

# Future SOP

## UniFi Device Adoption Checklist

1. Factory reset
2. Verify DHCP
3. Ping device
4. SSH to device
5. Run

```bash
info
```

6. Verify Inform Host
7. Verify Docker controller
8. Verify port 8080
9. Test `/inform`
10. Execute

```bash
set-inform http://<controller-ip>:8080/inform
```

11. Wait
12. Execute a second time if necessary
13. Verify topology

---

# Suggested Git Commit

```
feat(unifi):
Completed commissioning of portable UniFi test rack.

- Successfully adopted Lite 8 PoE
- Successfully adopted U6+
- Investigated Docker-hosted controller adoption failures
- Documented Inform Host troubleshooting workflow
- Added UniFi device adoption SOP
```

---

# Understanding Check

> **"...since this rack is on my network, the AP...is essentially supplementing my Techworks AP, right?"**

**Yes. Exactly.**

Right now your network looks like this:

```
                  Production Switch
                         │
        ┌────────────────┴──────────────┐
        │                               │
        ▼                               ▼
   U7 Pro Max                  Test Rack Switch
                                        │
                                        ▼
                                      U6+
```

Both APs are:

* On the same Layer 2 network.
* Broadcasting the same SSID (`TechworksAP`).
* Managed by the same UniFi controller.
* Serving clients as a single wireless infrastructure.

From a client's perspective, there is just **one Wi-Fi network**. The controller handles client association, and devices decide when to roam based on signal strength and their own roaming algorithms.

Your screenshot actually demonstrates this. Your TestBench client is connected to the **U6+** at **-35 dBm**, while other devices are connected through the **U7 Pro Max**. That's exactly how multiple APs are supposed to work together.

---



