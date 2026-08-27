MON-002 --- Scheduled WAN Performance Monitoring

Portfolio Project

Category: Monitoring / Observability
Platform: Linux, Prometheus, Grafana, Node Exporter, systemd
Purpose: Build a lightweight, automated method for measuring WAN
performance over time without continuously consuming bandwidth.

Sanitization note: Hostnames, internal IP addresses, firewall
source addresses, and other environment-specific identifiers have been
generalized for public portfolio use.

1. Project Overview

After implementing Internet availability and outage monitoring, I wanted
a second monitoring layer that answered a different question:

Am I receiving consistent WAN performance from my Internet service
over time?

Continuous bandwidth testing would generate unnecessary traffic and
could itself affect network performance. Instead, I designed a scheduled
measurement system that runs an Ookla Speedtest four times per day and
exposes the results as Prometheus metrics.

The measurements are collected on a dedicated Linux monitoring node and
visualized in Grafana alongside existing WAN availability and
interface-utilization data.

This project extends availability monitoring with periodic measurements
of:

Download throughput

Upload throughput

Packet loss

Idle latency

Loaded download latency

Loaded upload latency

Latency jitter

Timestamp of the most recent successful test

2. Why I Built It

My existing monitoring could determine whether Internet connectivity was
available and identify outages, but availability alone does not describe
connection quality.

A WAN connection can technically remain UP while experiencing:

Reduced throughput

Packet loss

High jitter

Increased latency under load

Intermittent degradation

I therefore wanted historical evidence of both availability and
performance.

The design goal was to collect enough data to identify trends without
turning the monitoring system itself into a significant bandwidth
consumer.

A six-hour test interval was selected, resulting in approximately four
measurements per day.

3. Architecture

                  Scheduled every 6 hours
                           │
                           ▼
                ┌─────────────────────┐
                │ Linux Measurement   │
                │ Node                │
                │                     │
                │ Ookla Speedtest CLI │
                └──────────┬──────────┘
                           │
                           ▼
                ┌─────────────────────┐
                │ Bash Metrics        │
                │ Collector           │
                └──────────┬──────────┘
                           │
                           ▼
                speedtest.prom
                           │
                           ▼
                ┌─────────────────────┐
                │ Prometheus          │
                │ Node Exporter       │
                │ Textfile Collector  │
                └──────────┬──────────┘
                           │
                   TCP/9100 restricted
                   to monitoring host
                           │
                           ▼
                ┌─────────────────────┐
                │ Prometheus Server   │
                └──────────┬──────────┘
                           │
                           ▼
                ┌─────────────────────┐
                │ Grafana Dashboard   │
                └─────────────────────┘

Data Flow

A systemd timer triggers the Speedtest metrics service.

The service executes the Ookla Speedtest CLI.

A Bash collector extracts the desired measurements.

Results are written in Prometheus exposition format.

Node Exporter's textfile collector publishes the metrics.

Prometheus scrapes Node Exporter.

Grafana queries Prometheus and visualizes the measurements.

4. Technologies Used

Technology                 Purpose

Ubuntu Linux               Measurement and monitoring hosts
Ookla Speedtest CLI        WAN performance testing
Bash                       Metrics collection and transformation
systemd service            Executes the collection workload
systemd timer              Schedules execution every six hours
Docker                     Runs the existing Node Exporter deployment
Prometheus Node Exporter   Exposes host and custom metrics
Textfile Collector         Publishes custom Speedtest metrics
Prometheus                 Time-series collection and retention
Grafana                    Dashboard visualization
UFW                        Restricts access to the metrics endpoint

5. Metrics Exposed

The collector exports the following Prometheus metrics:

speedtest_download_mbps
speedtest_upload_mbps
speedtest_idle_latency_ms
speedtest_idle_jitter_ms
speedtest_download_latency_ms
speedtest_download_jitter_ms
speedtest_upload_latency_ms
speedtest_upload_jitter_ms
speedtest_packet_loss_percent
speedtest_last_run_timestamp

Example sanitized output:

# HELP speedtest_download_mbps Measured download throughput in megabits per second.
# TYPE speedtest_download_mbps gauge
speedtest_download_mbps 611.75

# HELP speedtest_upload_mbps Measured upload throughput in megabits per second.
# TYPE speedtest_upload_mbps gauge
speedtest_upload_mbps 42.24

# HELP speedtest_idle_latency_ms Idle network latency in milliseconds.
# TYPE speedtest_idle_latency_ms gauge
speedtest_idle_latency_ms 10.554

# HELP speedtest_packet_loss_percent Packet loss percentage reported by Speedtest.
# TYPE speedtest_packet_loss_percent gauge
speedtest_packet_loss_percent 2.62

6. Scheduling Strategy

Rather than run continuous tests, I configured a systemd timer to
execute the collector every six hours.

This provides:

Four measurements per day

Low monitoring overhead

Reduced bandwidth consumption

Historical performance samples

Enough data to identify recurring degradation

The timer can be verified with:

systemctl status speedtest-metrics.timer --no-pager

and:

systemctl list-timers speedtest-metrics.timer

This design also separates scheduling from metric collection,
making the implementation easier to troubleshoot and maintain.

7. Node Exporter Textfile Collector

The Speedtest measurements are not native Node Exporter metrics.

To integrate them cleanly with the existing Prometheus environment, I
used Node Exporter's textfile collector.

The collector writes the most recent measurements to a .prom file in
the configured textfile collector directory.

The exported metrics can be validated locally with:

curl -s http://localhost:9100/metrics | grep '^speedtest_'

This was an important architectural decision because it avoided
deploying an additional custom exporter or web service simply to expose
a small set of periodically generated metrics.

8. Troubleshooting: Port 9100 Conflict

Symptom

After installing the operating-system Node Exporter package, the service
repeatedly failed:

listen tcp :9100: bind: address already in use

Investigation

I identified the process already listening on TCP port 9100:

sudo ss -ltnp | grep ':9100'

I then identified the running process:

ps aux | grep '[n]ode_exporter'

Docker inspection revealed that Node Exporter was already running as a
container using host networking.

sudo docker ps

Additional inspection established its deployment characteristics:

sudo docker inspect node-exporter

Root Cause

This was not a broken Node Exporter installation.

There were two competing Node Exporter deployments:

An existing Docker container

A newly installed systemd-managed package

Both attempted to bind TCP port 9100.

Resolution

Rather than replacing a working deployment unnecessarily, I retained the
existing Docker-based Node Exporter and extended it to support the
textfile collector.

This preserved the existing monitoring architecture and avoided
introducing a duplicate service.

Lesson

Before replacing or repairing a failed service, determine whether the
requested resource is already owned by another process.

Useful diagnostic sequence:

ss -ltnp
ps aux
docker ps
docker inspect
systemctl status

The error message identified the immediate problem; process and
container inspection identified the actual architecture.

9. Troubleshooting: Prometheus Could Not Reach Node Exporter

Symptom

Node Exporter worked locally on the measurement host, but Prometheus
initially reported the target as:

up = 0

A remote connection to TCP/9100 stalled.

Investigation

The measurement host's firewall configuration was reviewed:

sudo ufw status verbose

The host used a default-deny inbound firewall policy, and TCP/9100 had
not been permitted.

Resolution

Rather than expose Node Exporter broadly, firewall access was restricted
to the Prometheus monitoring host.

Conceptually:

ALLOW TCP/9100
SOURCE: Prometheus monitoring server only
DESTINATION: measurement node

After the firewall rule was applied, remote validation succeeded:

curl --connect-timeout 5 http://<measurement-node>:9100/metrics

Prometheus subsequently reported:

up = 1

Security Lesson

Monitoring endpoints should not automatically be exposed to an entire
network merely because monitoring requires access.

The principle used here was:

Permit the required protocol from the required monitoring source only.

10. End-to-End Validation

I validated each layer independently rather than assuming that a working
dashboard meant the entire pipeline was configured correctly.

Layer 1 --- Metric File

cat /var/lib/node-exporter/textfile_collector/speedtest.prom

Layer 2 --- Node Exporter

curl -s http://localhost:9100/metrics | grep '^speedtest_'

Layer 3 --- Network Reachability

From the Prometheus host:

curl --connect-timeout 5 http://<measurement-node>:9100/metrics

Layer 4 --- Prometheus Target

up{job="node-exporter"}

Expected result for the measurement node:

1

Layer 5 --- Prometheus Metric

speedtest_download_mbps

and:

speedtest_packet_loss_percent

Layer 6 --- Grafana

The final metrics were visualized as dedicated time-series panels.

This layered validation method proved useful because each component
could be tested independently:

Speedtest
   ↓
.prom file
   ↓
Node Exporter
   ↓
Network / Firewall
   ↓
Prometheus
   ↓
Grafana

11. Grafana Dashboard

The final WAN monitoring dashboard combines two complementary monitoring
strategies.

Continuous WAN Observability

Existing monitoring provides:

Internet connectivity state

Internet latency

Recent availability percentage

Firewall/WAN state

WAN interface upload utilization

WAN interface download utilization

Scheduled WAN Performance

MON-002 adds:

Speedtest Download

Speedtest Upload

Packet Loss

Speedtest Latency

The Speedtest Latency panel compares:

speedtest_idle_latency_ms

speedtest_download_latency_ms

speedtest_upload_latency_ms

with legends:

Idle
Download Loaded
Upload Loaded

This makes it possible to compare baseline latency with latency
experienced while the WAN connection is under load.

12. Understanding the Dashboard

An important distinction is maintained between interface utilization
and Speedtest performance.

WAN Interface Utilization

SNMP-derived WAN panels answer:

How much traffic is traversing the WAN interface right now?

Example:

rate(ifHCInOctets{job="netgate-snmp",ifAlias="WAN"}[5m]) * 8 / 1000000

Speedtest Throughput

Speedtest panels answer:

How much throughput did the connection achieve during the scheduled
measurement?

These are different metrics and should not be interpreted
interchangeably.

A 600 Mbps Speedtest result does not mean the WAN interface
continuously carries 600 Mbps.

13. Observed Results

During implementation and testing, representative measurements included:

Measurement                                                Approximate Result

Download throughput                                                 600+ Mbps
Upload throughput                                                   ~42 Mbps
Idle latency                                                      ~10--13 ms
Loaded download latency                                              ~60+ ms
Loaded upload latency                                             ~30--40 ms
Packet loss                 Variable; several percent observed during testing

The testing also demonstrated why a single bandwidth measurement is
insufficient for assessing WAN quality.

High throughput could coexist with measurable packet loss and increased
latency under load.

14. Operational Lessons Learned

Availability and performance are different

A link can remain operational while providing degraded service.

Monitoring should therefore answer both:

Is it reachable?

and:

How well is it performing?

Throughput alone is insufficient

Download speed is only one dimension of network quality.

Packet loss, jitter, idle latency, and loaded latency can reveal
problems that a headline Mbps measurement hides.

Validate the entire telemetry pipeline

A metric can exist on a host without being available to Prometheus.

A Prometheus target can exist without being reachable.

A reachable exporter can exist without exposing the desired custom
metric.

Troubleshooting each layer independently significantly reduces
ambiguity.

Inspect before replacing

The TCP/9100 conflict demonstrated why service discovery is important.

The correct response to:

address already in use

was not immediately to kill the process.

It was to determine:

What owns this port?
Why is it running?
Is it part of the existing architecture?
Should I replace it or integrate with it?

Least privilege applies to monitoring

Exporter ports should be treated as infrastructure services and
restricted appropriately.

15. Skills Demonstrated

This project demonstrates practical experience with:

Linux administration

systemd services and timers

Bash scripting

Docker container inspection

TCP port troubleshooting

Process inspection

Host firewall configuration

Prometheus architecture

Prometheus exposition format

Node Exporter

Node Exporter textfile collector

PromQL

Grafana dashboard construction

SNMP-derived network metrics

Network latency analysis

Packet-loss analysis

WAN performance troubleshooting

Layered fault isolation

Observability design

Security-conscious monitoring architecture

Technical documentation

16. Relationship to MON-001

MON-001 --- Internet Availability and Outage Monitoring

answers:

Is the Internet reachable, and where does a connectivity failure
appear to occur?

MON-002 --- Scheduled WAN Performance Monitoring

answers:

What level of WAN performance is being delivered over time?

Together they provide two complementary layers of WAN observability:

MON-001
Availability / Reachability
        +
MON-002
Performance / Quality
        =
WAN Observability

17. Portfolio Summary

I designed and implemented a scheduled WAN performance monitoring
pipeline using Ookla Speedtest, Bash, systemd, Node Exporter's textfile
collector, Prometheus, and Grafana.

The system executes performance tests every six hours, converts the
results into Prometheus-compatible metrics, restricts exporter access to
the monitoring server, and visualizes historical throughput, packet
loss, and latency.

During implementation, I diagnosed a TCP/9100 service conflict caused by
competing Node Exporter deployments, inspected the existing Docker
architecture, retained and extended the appropriate exporter, identified
a host-firewall connectivity issue, and validated the complete telemetry
path from metric generation through Grafana.

The project complements continuous availability monitoring by
demonstrating that WAN health requires observing both reachability
and service quality.

18. Resume-Ready Project Description

Scheduled WAN Performance Monitoring --- Linux / Prometheus /
Grafana

Built an automated WAN performance monitoring pipeline using Linux,
Bash, systemd, Ookla Speedtest, Node Exporter, Prometheus, and Grafana.
Scheduled four daily performance measurements and exported throughput,
packet loss, jitter, and latency metrics through the Node Exporter
textfile collector. Diagnosed a TCP/9100 service conflict between
containerized and systemd Node Exporter deployments, implemented
source-restricted firewall access for Prometheus scraping, and validated
telemetry end-to-end from metric generation through dashboard
visualization.

