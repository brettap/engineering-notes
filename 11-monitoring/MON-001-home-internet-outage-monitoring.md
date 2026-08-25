# MON-001 — Home Internet Outage Monitoring

| Field | Value |
|---|---|
| Document ID | MON-001 |
| Document type | Operational runbook and rebuild/learning guide |
| Monitoring host | `ubuntu-devops01` |
| Project directory | `/home/brettcoder/monitoring-lab` |
| Dashboard | Home Internet Outage Monitoring |
| Components | Prometheus, Grafana, Blackbox Exporter, Netgate SNMP |
| Status | Documented operational baseline |
| Last documented | 2026-08-25 |

## 1. Purpose

This document is both a day-to-day incident runbook and a breadcrumb trail for rebuilding the Home Internet Outage Monitoring dashboard. It records not only what was built, but where settings are located in Grafana, what each query means, and how to interpret the evidence.

The dashboard is intended to answer four questions:

1. Was the local gateway reachable?
2. Was the Internet reachable, and was it slow before or during the event?
3. What was happening on the Netgate WAN interface at the same time?
4. Does the combined evidence point toward the LAN, Netgate, ISP path, a remote destination, or the monitoring stack?

The dashboard supports diagnosis; it does not prove root cause by itself.

## 2. Monitoring architecture

```text
Local gateway and Internet probe targets
             │ ICMP/HTTP probes
             ▼
      Blackbox Exporter ─────────────┐
      probe_success                  │
      probe_duration_seconds         │
                                     ▼
Netgate firewall ── SNMP ───────► Prometheus ─────► Grafana
WAN state, octets, errors,          time-series     Home Internet
and discards                        storage         Outage Monitoring

All monitoring services are operated from:
ubuntu-devops01:/home/brettcoder/monitoring-lab
```

### Component roles

| Component | Role |
|---|---|
| `ubuntu-devops01` | Linux host running the monitoring lab |
| `/home/brettcoder/monitoring-lab` | Working directory for the monitoring stack and its Compose/configuration files |
| Blackbox Exporter | Actively probes the gateway and external targets |
| Prometheus | Scrapes and retains Blackbox and Netgate SNMP metrics |
| Grafana | Queries Prometheus and correlates the signals visually |
| Netgate SNMP | Supplies WAN interface state, traffic counters, errors, and discards |

## 3. Before using or rebuilding the dashboard

On `ubuntu-devops01`:

```bash
cd /home/brettcoder/monitoring-lab
docker compose ps
```

All expected containers should be running. Confirm Prometheus scrape health at **Prometheus → Status → Targets** (normally `http://<prometheus-host>:9090/targets`). The Blackbox Internet job and `netgate-snmp` job should be `UP`.

Useful service checks:

```bash
cd /home/brettcoder/monitoring-lab
docker compose logs --tail=100 prometheus
docker compose logs --tail=100 blackbox-exporter
docker compose logs --tail=100 grafana
curl -fsS http://<prometheus-host>:9090/-/ready
curl -fsS http://<blackbox-host>:9115/metrics
```

Compose service names may differ. Use `docker compose ps` before requesting logs.

## 4. Dashboard inventory

| Panel | Visualization | Question answered |
|---|---|---|
| Internet Connectivity State | State timeline | Which target was down, and when? |
| Internet Latency | Time series | Was the connection slow or degrading? |
| Internet Availability — Last Hour | Stat | What percentage of the preceding hour was the external target reachable? |
| WAN Status | Stat or State timeline | Was the Netgate WAN interface operational? |
| WAN Download | Time series | How much inbound WAN traffic was received? |
| WAN Upload | Time series | How much outbound WAN traffic was sent? |
| WAN Errors | Time series | Were malformed/corrupt packets counted? |
| WAN Discards | Time series | Were otherwise valid packets dropped by the interface or device? |

## 5. General Grafana breadcrumbs

- Open the dashboard: **Grafana → Dashboards → Home Internet Outage Monitoring**.
- Add a panel: **Dashboard → Add → Visualization**.
- Edit a panel: **Panel title menu → Edit**.
- Select Prometheus: **Panel editor → Queries → Data source → Prometheus**.
- Enter PromQL: **Panel editor → Queries → Query A → Code**.
- Set the panel type: **Panel editor → Visualization picker**.
- Set a unit: **Panel editor → right sidebar → Standard options → Unit**.
- Set a friendly series name: **Panel editor → Queries → Query A → Options → Legend**.
- Set thresholds: **Panel editor → right sidebar → Thresholds**.
- Set value mappings: **Panel editor → right sidebar → Value mappings**.
- Save a panel: **Panel editor → Apply**.
- Save the dashboard: **Dashboard toolbar → Save dashboard**.

After a material edit, select both **Apply** and **Save dashboard**. A panel applied to an unnamed or unsaved dashboard can be lost when navigating away.

## 6. Internet connectivity panels

### 6.1 Internet Connectivity State

PromQL:

```promql
probe_success{job="internet",instance=~"192.168.1.1|1.1.1.1|8.8.8.8"}
```

Rebuild breadcrumbs:

1. **Dashboard → Add → Visualization → Prometheus**.
2. Enter the query above.
3. **Visualization → State timeline**.
4. **Queries → Query A → Options → Legend → Custom**: enter `{{instance}}`.
5. **Value mappings → Add mapping → Value**: map `1` to `UP` in green.
6. Add another exact-value mapping: map `0` to `DOWN` in red.
7. Remove the default numeric `80` threshold; it is meaningless for a binary metric.
8. Use **Color scheme → Classic palette (by series name)** if required for the explicit mapping colors in Grafana 12.4.
9. Set the title to `Internet Connectivity State`, apply, and save the dashboard.

Interpretation:

| Pattern | Working interpretation |
|---|---|
| Gateway UP; both external targets DOWN | WAN, ISP, or upstream path is suspect |
| Gateway DOWN; external targets DOWN | Local gateway/LAN path or monitoring-host connectivity is suspect |
| One external target DOWN; others UP | Destination-specific route, target, or probe problem is more likely |
| Blank segment | No data; it is not proof of downtime |

The gateway probe was added after the original external probes. Its earlier blank history must remain no-data, not be reclassified as an outage.

### 6.2 Internet Latency

PromQL:

```promql
probe_duration_seconds{job="internet",instance=~"1.1.1.1|8.8.8.8|google.com"} * 1000
```

Breadcrumbs: **Panel → Edit → Queries → Query A → Code**, then **Visualization → Time series** and **Standard options → Unit → Time → milliseconds (ms)**. Use `{{instance}}` for the legend.

Blackbox Exporter reports seconds; multiplying by `1000` displays milliseconds. Grafana may abbreviate large millisecond values as seconds on an axis without changing the query result. A `google.com` series appears only if that exact target exists in Prometheus.

### 6.3 Internet Availability — Last Hour

PromQL:

```promql
avg_over_time(probe_success{job="internet",instance="1.1.1.1"}[1h]) * 100
```

Breadcrumbs: **Panel → Edit → Visualization → Stat**, then **Standard options → Unit → Misc → Percent (0-100)**. Set absolute thresholds to Base/red, `99`/yellow, and `99.9`/green.

This is a rolling one-hour measure. A failed probe continues to affect it until that sample ages out of the window; it is not availability over the entire dashboard time range.

## 7. Netgate WAN panels

First verify the labels and exact metric names exposed in this environment:

```promql
count by (ifAlias, ifDescr, instance) ({job="netgate-snmp"})
```

The baseline filters the WAN interface with both `job="netgate-snmp"` and `ifAlias="WAN"`. If a query returns no data, inspect the labels in **Grafana → Explore → Prometheus** rather than silently removing the WAN filter.

### 7.1 WAN Status

Typical IF-MIB PromQL:

```promql
ifOperStatus{job="netgate-snmp",ifAlias="WAN"}
```

Use a Stat or State timeline. For standard IF-MIB values, map `1` to `UP`/green and `2` to `DOWN`/red. Confirm the exporter’s returned values before relying on mappings.

Breadcrumbs: **Dashboard → Add → Visualization → Prometheus → enter query → Stat**, then **Value mappings → Add mapping → Value**.

### 7.2 WAN download and upload

Preferred 64-bit interface counters, converted from octets per second to bits per second:

```promql
rate(ifHCInOctets{job="netgate-snmp",ifAlias="WAN"}[5m]) * 8
```

```promql
rate(ifHCOutOctets{job="netgate-snmp",ifAlias="WAN"}[5m]) * 8
```

Use inbound as **Download** and outbound as **Upload** from the Netgate WAN interface’s perspective. Select **Standard options → Unit → Data rate → bits/sec (SI)**. If the exporter lacks `ifHCInOctets`/`ifHCOutOctets`, verify and use its 32-bit `ifInOctets`/`ifOutOctets` metrics, understanding that high-speed counter wrap is more likely.

### 7.3 WAN errors — exact queries

Inbound errors:

```promql
rate(ifInErrors{job="netgate-snmp",ifAlias="WAN"}[5m])
```

Outbound errors:

```promql
rate(ifOutErrors{job="netgate-snmp",ifAlias="WAN"}[5m])
```

Place both queries in one Time series panel when directional comparison is useful. Set the unit to **packets/sec (pps)** and legends to fixed text such as `Inbound errors` and `Outbound errors`.

### 7.4 WAN discards — exact queries and required panel design

Query A — inbound:

```promql
rate(ifInDiscards{job="netgate-snmp",ifAlias="WAN"}[5m])
```

Query B — outbound:

```promql
rate(ifOutDiscards{job="netgate-snmp",ifAlias="WAN"}[5m])
```

Do **not** add the two queries together. The required design is two separate directional series in the same Time series panel so an operator can see whether drops are inbound, outbound, or simultaneous.

Rebuild breadcrumbs:

1. **Dashboard → Add → Visualization → Prometheus**.
2. **Queries → Query A → Code**: paste the inbound query.
3. **Query A → Options → Legend → Custom**: enter `Inbound discards`.
4. **Queries → Add query → Query B → Code**: paste the outbound query.
5. **Query B → Options → Legend → Custom**: enter `Outbound discards`.
6. **Visualization → Time series**.
7. **Standard options → Unit → Throughput → packets/sec (pps)**, or the equivalent packets-per-second unit in the installed Grafana version.
8. Title the panel `WAN Discards`, apply, and save the dashboard.

### Legend templates versus fixed text

Grafana replaces `{{label}}` with the value of a Prometheus label. For example, `{{instance}}` might render `1.1.1.1`; `{{ifAlias}}` might render `WAN`. The braces are a template, not decorative punctuation. If the named label is absent, the legend may be blank or unhelpful.

Fixed text such as `Inbound discards` is shown literally. Fixed legends are clearer when each query already has one known meaning. Label templates are better when one query intentionally returns multiple series that need to be distinguished by a label.

### Why Grafana shows milli packets/sec

`rate()` calculates an average per-second rate and can return fractional values. Grafana applies SI prefixes automatically. Therefore:

- `1 pps` means one packet per second;
- `1 mpps` in this Grafana context means one **milli-packet per second**, or `0.001 packets/second`;
- `20 mpps` means `0.020 packets/second`, averaging about one packet every 50 seconds.

This does not mean millions of packets per second. Mega uses an uppercase `M`; milli uses lowercase `m`. Hover over the series and check the selected unit before interpreting an abbreviation.

## 8. Understanding the queries

### What `rate(...[5m])` means

SNMP interface counters are cumulative totals. A raw counter normally rises for as long as the device remains up. `rate(counter[5m])` estimates the counter’s average per-second increase over the preceding five minutes and handles ordinary counter resets.

The five-minute window smooths brief changes and is more stable than a very short range, but it also spreads a short event across several displayed points. A spike’s graph time is an averaged window, not necessarily the exact packet-drop timestamp.

### Errors versus discards

| Counter type | Meaning |
|---|---|
| Errors | Packets that could not be processed because they were malformed, corrupt, or otherwise invalid at that interface |
| Discards | Packets that may have been valid but were intentionally dropped, commonly because of queue, buffer, policy, or resource pressure |

Errors can suggest a physical/link-quality or packet-integrity problem. Discards more often suggest congestion, queue pressure, resource limits, or policy. Neither counter alone proves the cause, and zeros do not prove that the ISP path was healthy beyond the observed Netgate interface.

## 9. Observed overnight behavior

The captured overnight period contained brief external probe failures and latency spikes approaching approximately `5000 ms`, near the probe timeout discussed during setup. The local gateway remained reachable during the portion for which it had data. Application playback/buffering was noticed around the same general period.

That correlation is operationally useful but not conclusive. Application buffering may arise from WAN loss, high latency, jitter, a destination/CDN issue, Wi-Fi/LAN behavior, or the application itself. Preserve exact timestamps and compare the Blackbox, WAN, and application observations before assigning root cause.

## 10. Xfinity XB8 investigation and routing limitation

The Xfinity XB8 was investigated as a possible source of additional signal or event history. In this topology, the visible management/routing hop was limited to `10.0.0.1`. That address can establish reachability to the XB8-side gateway, but it does not expose every internal Comcast/Xfinity hop or provide end-to-end visibility into the provider network.

Consequences:

- A successful response from `10.0.0.1` does not prove that the Internet beyond the XB8 is healthy.
- A route that stops at, or exposes only, `10.0.0.1` is not enough to locate a downstream ISP fault.
- XB8 UI/event evidence, Xfinity outage information, and timestamps should be treated as separate corroborating evidence.
- Do not invent unavailable upstream hop data; document the visibility limit explicitly.

## 11. Incident-correlation workflow

1. Record the user-visible symptom, application, device, and exact local time/time zone.
2. Open **Grafana → Dashboards → Home Internet Outage Monitoring** and set a narrow time range around the event, then widen it for context.
3. Check **Internet Connectivity State**. Determine whether the gateway, one external target, or all external targets failed.
4. Check **Internet Latency** for degradation or a timeout plateau before/during the failure.
5. Check **WAN Status** for a Netgate interface transition.
6. Compare **WAN Download** and **WAN Upload** for saturation or an abrupt traffic stop.
7. Compare separate inbound/outbound **WAN Errors** and **WAN Discards**. Note direction, magnitude, and duration.
8. Check Prometheus target health and container logs so a scrape failure is not mistaken for an Internet outage.
9. Compare Xfinity/XB8 evidence, remembering that route visibility is limited to `10.0.0.1`.
10. Write a timeline that distinguishes fact from inference.

Suggested incident note:

```text
Time (America/New_York):
User symptom/application:
Gateway probe:
External probes:
Latency:
WAN operational state:
Download/upload:
Inbound/outbound errors:
Inbound/outbound discards:
Prometheus scrape health:
XB8/Xfinity evidence:
Working interpretation:
Confidence and missing evidence:
```

## 12. Validation checks

### Data-source validation

Run in **Grafana → Explore → Prometheus** or the Prometheus expression browser:

```promql
count by (instance) (probe_success{job="internet"})
```

```promql
up{job=~"internet|netgate-snmp"}
```

```promql
count by (ifAlias) (ifInDiscards{job="netgate-snmp"})
```

Expected results:

- the configured gateway and external targets are present;
- both scrape jobs report healthy targets;
- the Netgate metrics include `ifAlias="WAN"`;
- the four error/discard queries execute without parse errors;
- brief zeros are displayed as zeros, while missing samples remain no-data.

### Dashboard validation

- Connectivity rows use readable target names, not full label sets.
- `1` displays as green `UP`; `0` displays as red `DOWN`.
- Latency is shown in milliseconds.
- Availability uses Percent (0–100), not Percent (0.0–1.0).
- WAN download and upload are directionally correct from the WAN interface perspective.
- WAN Discards contains two visible series named `Inbound discards` and `Outbound discards`.
- Errors and discards use packets/sec; low values may legitimately display in milli packets/sec.
- The panel and dashboard are both saved.

## 13. Troubleshooting breadcrumbs

### A query returns no data

Go to **Grafana → Explore → Prometheus**, run the metric name without the `ifAlias` filter, expand a returned series, and inspect its labels. Confirm the scrape at **Prometheus → Status → Targets**. A label mismatch, scrape outage, or unsupported metric is not the same as a genuine zero.

### A timeline shows `< 80` or `-∞+`

Go to **Panel → Edit → right sidebar → Thresholds** and remove the default `80`. Then verify **Value mappings** contains exact values `1 → UP` and `0 → DOWN`.

### A row shows a full Prometheus label set

Go to **Panel → Edit → Queries → Query → Options → Legend → Custom** and use `{{instance}}`, or use intentional fixed text for single-purpose queries.

### Availability is red at 100%

Go to **Panel → Edit → Thresholds**, select Absolute mode, and set Base red, `99` yellow, and `99.9` green.

### Availability does not immediately recover

This is expected for `avg_over_time(...[1h])`. Failed samples remain in the rolling hour until they age out.

### A panel disappeared

Return to **Grafana → Dashboards → Home Internet Outage Monitoring** and confirm the correct saved dashboard is open. Applying a panel and saving the dashboard are separate actions.

## 14. Lessons learned

- Define the operational question before styling the visualization.
- Keep inbound and outbound series separate. Adding them hides the direction needed for diagnosis.
- Prometheus label filters must match the exporter’s actual labels exactly.
- A legend template such as `{{instance}}` resolves a label; fixed text describes a known query.
- Counter totals are less useful operationally than a rate over a defined window.
- A five-minute rate improves readability but reduces timestamp precision for short events.
- Milli packets/sec is a fractional average, not automatically a large packet rate.
- Missing data is not downtime, and correlation is not causation.
- A healthy local gateway plus failed external probes narrows the problem but does not by itself prove an ISP fault.
- Monitoring-stack health must be checked before treating a graph gap as a network event.
- Save both the panel and the dashboard, and preserve navigation breadcrumbs for future rebuilding.

## 15. Command and PromQL quick reference

```bash
ssh ubuntu-devops01
cd /home/brettcoder/monitoring-lab
docker compose ps
docker compose logs --tail=100 prometheus
docker compose logs --tail=100 blackbox-exporter
docker compose logs --tail=100 grafana
```

```promql
probe_success{job="internet",instance=~"192.168.1.1|1.1.1.1|8.8.8.8"}
```

```promql
probe_duration_seconds{job="internet",instance=~"1.1.1.1|8.8.8.8|google.com"} * 1000
```

```promql
avg_over_time(probe_success{job="internet",instance="1.1.1.1"}[1h]) * 100
```

```promql
rate(ifInErrors{job="netgate-snmp",ifAlias="WAN"}[5m])
```

```promql
rate(ifOutErrors{job="netgate-snmp",ifAlias="WAN"}[5m])
```

```promql
rate(ifInDiscards{job="netgate-snmp",ifAlias="WAN"}[5m])
```

```promql
rate(ifOutDiscards{job="netgate-snmp",ifAlias="WAN"}[5m])
```

Prometheus API example:

```bash
curl -G -fsS http://<prometheus-host>:9090/api/v1/query \
  --data-urlencode 'query=probe_success{job="internet"}'
```

## 16. Future improvements

- Add alert rules for sustained external probe failure, high latency, WAN state change, and non-zero error/discard rates.
- Add packet-loss and jitter measurements rather than inferring them from probe success and duration.
- Add dashboard annotations for user-reported buffering and confirmed Xfinity events.
- Retain longer history and define a backup/restore procedure for Prometheus and Grafana.
- Export/version the Grafana dashboard JSON alongside this document.
- Add recording rules if repeated five-minute SNMP queries become expensive.
- Establish event thresholds from a measured baseline rather than arbitrary values.
- Add an incident log with local time, UTC time, duration, evidence, and final disposition.
- Investigate additional supported XB8/Xfinity telemetry while preserving the documented `10.0.0.1` visibility limit.

## 17. Documentation status and change control

MON-001 is the current Git-ready operational baseline and rebuild guide for this monitoring work. It records the known dashboard behavior and the evidence available at the time of documentation. Host addresses, exporter versions, interface labels, and Compose service names should be revalidated after infrastructure changes.

When changing the dashboard:

1. record the reason and expected result;
2. change one behavior at a time;
3. validate query data, labels, units, mappings, no-data behavior, and directionality;
4. save the panel and dashboard;
5. export updated dashboard JSON if it is version-controlled; and
6. update this document and its date/status.

## 18. Suggested Git commands

From the repository that will contain this file:

```bash
git status
git add MON-001-Home-Internet-Outage-Monitoring.md
git diff --cached -- MON-001-Home-Internet-Outage-Monitoring.md
git commit -m "docs: add MON-001 home internet monitoring runbook"
git push
```

Review `git status` and the staged diff before committing. If the branch has no upstream yet, use the branch name shown by `git branch --show-current` with `git push -u origin <branch-name>`.
