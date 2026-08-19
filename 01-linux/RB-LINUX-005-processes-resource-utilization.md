# RB-LINUX-005 — Linux Processes and Resource Utilization Troubleshooting

**Lab:** Linux Administration Lab #005
**Incident:** INC-5001 — DevOps02 Performance Degradation
**System:** DevOps02
**IP:** `192.168.1.137`
**Environment:** Ubuntu VM on Proxmox
**Topics:** Processes, CPU, `top`, `htop`, `ps`, PIDs, signals, resource monitoring
**Status:** COMPLETE / VERIFIED

---

# 1. Purpose

This runbook documents a structured procedure for investigating Linux server performance degradation.

The lab simulated a common infrastructure incident:

> Users report that a Linux server has become unusually slow.

The objective was to determine:

1. Which system resource was constrained.
2. Which processes were responsible.
3. Who owned those processes.
4. What commands/applications the processes represented.
5. Whether the processes were legitimate.
6. The safest remediation.
7. Whether remediation actually restored performance.

---

# 2. Incident

## INC-5001 — DevOps02 Performance Degradation

**Priority:** P2
**System:** DevOps02 — `192.168.1.137`

Reported symptom:

```text id="xyhfc9"
Users report that DevOps02
has become unusually slow.

SSH remains available.

Applications and commands appear
less responsive than normal.
```

Initial failure domain was unknown.

Possible causes included:

```text id="d5tx4s"
                    SERVER SLOW
                         │
        ┌────────────────┼────────────────┐
        │                │                │
       CPU              RAM             Disk
        │                │                │
        │                │          ┌─────┴─────┐
        │                │          │           │
        │                │       Capacity      I/O
        │                │
        └────────────────┼────────────────┐
                         │                │
                      Process         Network/
                      workload        application
```

Do not assume that "server slow" means CPU utilization.

Identify the constrained resource first.

---

# 3. Controlled Incident Injection

For training purposes, two CPU-intensive processes were deliberately created.

```bash id="38wdcu"
nohup yes > /dev/null 2>&1 &
nohup yes > /dev/null 2>&1 &
```

These commands were used only to create a controlled lab condition.

They are **not part of the normal troubleshooting procedure**.

---

# 4. Initial Resource Investigation

The server was inspected using:

```bash id="x5fys9"
top
```

and:

```bash id="pd77dd"
htop
```

Both tools allow real-time inspection of system resource utilization and running processes.

The investigation established that:

```text id="dwuv1x"
CPU utilization
      │
      ▼
Approximately 100%
      │
      ▼
CPU identified as
constrained resource
```

---

# 5. Using `top`

Run:

```bash id="v1t5sv"
top
```

`top` provides a continuously updated view of system activity.

Useful information includes:

* CPU utilization
* memory utilization
* load averages
* running/sleeping processes
* PID
* process owner
* per-process CPU utilization
* per-process memory utilization
* process command

Conceptually:

```text id="xt48x9"
                    top

System
├── load average
├── CPU
├── memory
├── swap
└── processes
     │
     ├── PID
     ├── USER
     ├── %CPU
     ├── %MEM
     └── COMMAND
```

`top` is normally available on Linux systems without requiring additional software.

---

# 6. Using `htop`

Run:

```bash id="bh2ncd"
htop
```

`htop` provides an interactive process/resource view.

It can make it easier to visually identify:

* heavily utilized CPU cores;
* high-CPU processes;
* memory utilization;
* process ownership;
* process relationships;
* individual PIDs.

In this incident, both `top` and `htop` indicated severe CPU utilization.

---

# 7. Resource Triage Model

When the initial report is simply:

```text id="vb6stp"
"The server is slow."
```

use a layered approach:

```text id="ry5mx7"
                   SERVER SLOW
                        │
                        ▼
                Observe resources
                   top / htop
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
       CPU             Memory           Other
        │               │               │
     high?           exhausted?      investigate
        │
        ▼
Identify process
        │
        ▼
Identify PID
        │
        ▼
Identify owner
        │
        ▼
Identify command
        │
        ▼
Determine legitimacy
        │
        ▼
Remediate
        │
        ▼
Verify baseline
```

---

# 8. Processes Identified

The investigation found two processes consuming the CPU resources:

```text id="1l4q08"
PID 3944
PID 3945
```

Both processes were associated with:

```text id="xofqeb"
yes
```

The owner was:

```text id="u7v3s6"
brettcoder
```

---

# 9. Investigating a PID

Once a suspicious PID has been identified, gather additional information before terminating it.

## Get Process Name

```bash id="m2ypb2"
ps -p 3944 -o comm=
```

This answers:

> What executable/process corresponds to this PID?

Result:

```text id="f2fcd2"
yes
```

---

# 10. Get Full Process Details

Use:

```bash id="uj0fdq"
ps -fp 3944
```

This provides additional process information such as:

* UID/owner
* PID
* parent PID
* start information
* command

This helped establish that the process belonged to the expected lab user.

---

# 11. Get Full Command String

Use:

```bash id="m5exnw"
ps -p 3944 -o args=
```

This displays the command and its arguments.

Generic syntax:

```bash id="87z13p"
ps -p <PID> -o args=
```

This becomes particularly useful when the process name alone is ambiguous.

For example:

```text id="rddc17"
COMMAND
python
```

does not necessarily tell the administrator which workload is running.

The arguments may reveal:

```text id="8n0edr"
python /srv/webapp/application.py
```

Likewise:

```text id="hl4x5c"
java
node
bash
python
```

may represent many different workloads.

Always gather enough context before terminating a production process.

---

# 12. What Is `yes`?

`yes` is a standard Unix/Linux utility that repeatedly outputs a string until terminated.

Without an argument:

```bash id="spbg8d"
yes
```

produces:

```text id="dnwn3g"
y
y
y
y
y
...
```

until interrupted.

It can be stopped interactively with:

```text id="60z0l1"
Ctrl+C
```

Because the program continuously generates output without naturally terminating, it can consume significant CPU resources.

---

# 13. Understanding the Incident Injection Command

The lab command was:

```bash id="juy1cm"
nohup yes > /dev/null 2>&1 &
```

Breakdown:

```text id="vwmldc"
nohup
  │
  └── allows the command to continue
      after terminal/session termination

yes
  │
  └── continuously generates output

> /dev/null
  │
  └── discard standard output

2>&1
  │
  └── redirect stderr to the same
      destination as stdout

&
  │
  └── execute in background
```

Operationally:

```text id="d1cdvf"
          yes
           │
           │ continuously generates data
           ▼
        CPU work
           │
           ▼
       /dev/null
           │
           ▼
     output discarded
```

Running two instances created the controlled CPU saturation condition.

---

# 14. Determine Whether a Process Is Legitimate

High CPU consumption does not automatically mean a process should be terminated.

Before remediation determine:

```text id="3kl3m9"
High CPU process
       │
       ▼
What process?
       │
       ▼
Who owns it?
       │
       ▼
What command launched it?
       │
       ▼
Expected workload?
      / \
    YES  NO
     │    │
     │    ▼
     │ investigate
     │
     ▼
Is utilization expected?
```

Examples of legitimate high CPU activity might include:

* backups;
* compression;
* database maintenance;
* software compilation;
* antivirus/security scans;
* batch processing;
* application workloads;
* scheduled jobs.

Do not terminate processes solely because `%CPU` is high.

---

# 15. Incident Assessment

For INC-5001:

```text id="hjy8pl"
Process: yes
Owner:   brettcoder
PIDs:    3944, 3945

Purpose:
Controlled lab workload

Required now?
NO
```

The processes were therefore safe to terminate.

---

# 16. Process Termination

The preferred initial termination method is:

```bash id="swh44v"
kill <PID>
```

Example:

```bash id="dlmeqi"
kill 3944
kill 3945
```

By default, `kill` normally sends:

```text id="8b7dfe"
SIGTERM — signal 15
```

Conceptually:

```text id="1knf3q"
Administrator
      │
      ▼
kill PID
      │
      ▼
SIGTERM
      │
      ▼
"Terminate cleanly"
      │
      ▼
Process performs cleanup
      │
      ▼
Process exits
```

---

# 17. SIGTERM vs SIGKILL

Do not immediately default to:

```bash id="e4e7wz"
kill -9 <PID>
```

`kill -9` sends:

```text id="31k69y"
SIGKILL — signal 9
```

The kernel terminates the process immediately.

Preferred sequence:

```text id="akp2fr"
Problem process
      │
      ▼
kill PID
SIGTERM
      │
      ▼
Did process exit?
   /       \
 YES        NO
  │          │
  │          ▼
  │     Investigate
  │          │
  │     Is force justified?
  │          │
  │          ▼
  │     kill -9 PID
  │       SIGKILL
  │
  ▼
Verify recovery
```

`SIGKILL` does not allow the process to perform normal cleanup.

Use it when forceful termination is justified, not merely because it is convenient.

---

# 18. Verify Process Termination

After remediation, verify that the processes are no longer present.

Example:

```bash id="mlztod"
ps -p 3944
ps -p 3945
```

Also inspect resource utilization again:

```bash id="z8opki"
top
```

or:

```bash id="9wiyha"
htop
```

The incident is not resolved merely because `kill` returned without an error.

---

# 19. Independent Hypervisor Verification

The Proxmox dashboard was used as a second source of evidence.

Before remediation:

```text id="w7vr2v"
             DevOps02

Linux top/htop
      │
      └── CPU ~100%
              │
              ▼
       Proxmox dashboard
              │
              └── CPU ~100%
```

After terminating the two processes:

```text id="khkxzx"
kill 3944
kill 3945
     │
     ▼
Linux CPU utilization
returns to baseline
     │
     ▼
Proxmox dashboard
also returns to baseline
     │
     ▼
INCIDENT VERIFIED
```

This provided independent corroboration that the resource problem had actually been corrected.

---

# 20. Why Multiple Monitoring Perspectives Matter

Different layers provide different evidence.

```text id="0gx14l"
                  Proxmox Host
                       │
                       │ VM-level metrics
                       ▼
                    DevOps02
                       │
                  top / htop
                       │
                       │ process-level metrics
                       ▼
                 PID / process
```

Proxmox can establish:

> The VM is consuming substantial CPU.

Linux process tools can establish:

> These specific processes inside the VM are responsible.

Together they reduce the failure domain.

---

# 21. Incident Resolution

```text id="imynvs"
INC-5001
   │
   ▼
Users report slow server
   │
   ▼
top / htop
   │
   ▼
CPU approximately 100%
   │
   ▼
Identify high-CPU PIDs
   │
   ├── 3944
   └── 3945
          │
          ▼
      ps inspection
          │
          ▼
     process = yes
     owner = brettcoder
          │
          ▼
Known test workload
          │
          ▼
No longer required
          │
          ▼
Terminate processes
          │
          ▼
CPU returns to baseline
          │
          ▼
Proxmox corroborates
          │
          ▼
       RESOLVED
```

---

# 22. Incident Summary

**Symptom:**
DevOps02 experienced severe performance degradation.

**Resource affected:**
CPU.

**Observed utilization:**
Approximately 100%.

**Responsible processes:**

```text id="u3o0pj"
PID 3944 → yes
PID 3945 → yes
```

**Process owner:**

```text id="c1f25i"
brettcoder
```

**Root cause:**
Two intentionally created, unbounded `yes` processes continuously generated output and consumed CPU resources.

**Remediation:**
The unnecessary processes were terminated.

**Verification:**

* Linux CPU utilization returned to baseline.
* `top`/`htop` confirmed resource recovery.
* Proxmox dashboard independently confirmed CPU utilization returned to normal.

**Status:** RESOLVED.

---

# 23. Command Reference

```bash id="svz38g"
# Interactive process/resource monitoring
top

# Enhanced interactive process monitoring
htop

# Get process name from PID
ps -p <PID> -o comm=

# Get process details
ps -fp <PID>

# Get complete command/arguments
ps -p <PID> -o args=

# Request normal process termination
kill <PID>

# Force termination — use only when justified
kill -9 <PID>

# Check whether PID still exists
ps -p <PID>
```

---

# 24. Resource Troubleshooting Workflow

```text id="4dmfdw"
                  "SERVER IS SLOW"
                         │
                         ▼
                    top / htop
                         │
                         ▼
              Identify constrained resource
                         │
             ┌───────────┼───────────┐
             │           │           │
            CPU         RAM         Other
             │           │           │
             ▼           ▼           ▼
        Find process   Investigate  Investigate
             │
             ▼
          Get PID
             │
             ▼
        Identify owner
             │
             ▼
       Identify command
             │
             ▼
       Understand purpose
             │
             ▼
        Legitimate process?
           /       \
         YES        NO
          │          │
    Determine if     │
    load expected    │
          │          │
          └────┬─────┘
               ▼
        Select remediation
               │
               ▼
          Apply change
               │
               ▼
         Verify locally
               │
               ▼
       Verify externally
               │
               ▼
            RESOLVED
```

---

# 25. Key Operational Principle

Do not use:

```text id="5wdghe"
High CPU
   ↓
Find PID
   ↓
kill -9
```

Use:

```text id="hufsk1"
High CPU
   ↓
Identify PID
   ↓
Identify process
   ↓
Identify owner
   ↓
Inspect full command
   ↓
Understand purpose
   ↓
Determine legitimacy
   ↓
Choose remediation
   ↓
SIGTERM first where appropriate
   ↓
Verify process state
   ↓
Verify resource recovery
```

The objective is not merely to stop a process.

The objective is to understand **why the system is experiencing degradation and remediate it without unnecessarily disrupting legitimate workloads**.

---

# 26. Skills Exercised

This lab provided hands-on experience with:

* Linux process monitoring
* `top`
* `htop`
* CPU utilization
* PIDs
* process ownership
* `ps`
* process command inspection
* background processes
* stdout/stderr redirection
* `/dev/null`
* `nohup`
* Unix signals
* `SIGTERM`
* `SIGKILL`
* process termination
* post-remediation verification
* hypervisor-level monitoring
* incident-response methodology

---

# 27. Lessons Learned

1. "The server is slow" is a symptom, not a diagnosis.

2. Determine the constrained resource before attempting remediation.

3. `top` and `htop` provide real-time visibility into Linux resources and processes.

4. PID identification allows investigation of an individual process.

5. Process names alone may not identify the actual workload.

6. `ps -p <PID> -o args=` can reveal the complete command line.

7. Process ownership provides important context.

8. High resource utilization does not automatically indicate a malfunction.

9. Determine whether a workload is legitimate before terminating it.

10. Prefer graceful termination with `SIGTERM` before considering `SIGKILL`.

11. A successful `kill` command does not by itself prove incident resolution.

12. Recheck the affected resource after remediation.

13. Hypervisor metrics can independently corroborate guest OS observations.

14. Troubleshooting should move systematically from **symptom → resource → process → cause → remediation → verification**.

---

# 28. Final Incident Architecture

```text id="kv1ahg"
                  PROXMOX
                     │
              CPU monitoring
                     │
                     ▼
                 DevOps02
                     │
              CPU ~100%
                     │
                 top / htop
                     │
            ┌────────┴────────┐
            ▼                 ▼
         PID 3944          PID 3945
            │                 │
            ▼                 ▼
           yes               yes
            │                 │
            └────────┬────────┘
                     │
              CPU saturation
                     │
                     ▼
               Performance
               degradation
                     │
                     ▼
                SIGTERM
                     │
                     ▼
            Processes terminate
                     │
                     ▼
             CPU returns normal
                     │
              ┌──────┴──────┐
              ▼             ▼
          top/htop        Proxmox
             ✓               ✓
              └──────┬──────┘
                     ▼
                  VERIFIED
```

---

# 29. Lab Completion

```text id="ykb2ut"
RB-LINUX-005
│
├── Performance symptom ............ IDENTIFIED
├── Resource constraint ............ CPU
├── top investigation .............. COMPLETE
├── htop investigation ............. COMPLETE
├── PID identification ............. COMPLETE
├── Process identification ......... COMPLETE
├── Process ownership .............. VERIFIED
├── Workload legitimacy ............ ASSESSED
├── Process remediation ............ COMPLETE
├── Local verification ............. PASS
├── Proxmox verification ........... PASS
└── INC-5001 ....................... RESOLVED
```

**Linux Administration Lab #005 — COMPLETE**
