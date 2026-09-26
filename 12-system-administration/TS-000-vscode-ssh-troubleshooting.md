# VS Code Remote-SSH — Bad Owner or Permissions on SSH Config

## Synopsis

VS Code Remote-SSH was unable to connect to the TechWorks Ubuntu management server at `192.168.1.114`.

VS Code invoked the local Windows OpenSSH client, but OpenSSH terminated before authentication with:

```text
Bad owner or permissions on C:\Users\brett\.ssh\config
```

The issue was isolated to NTFS permissions on the local Windows SSH configuration file.

The SSH configuration file inherited `FullControl` permission for another Windows account, `TWMGMT\admin`. Windows OpenSSH rejected the configuration because its security requirements do not permit the SSH configuration file to be accessible in this manner.

Simply removing the account with `icacls /remove` did not initially work because the permission was **inherited from the parent `.ssh` directory**.

The resolution was to:

1. Disable inheritance on the SSH `config` file while preserving its existing ACL entries.
2. Remove the unwanted `TWMGMT\admin` ACE.
3. Verify the resulting ACL.
4. Test SSH with verbose logging.
5. Confirm successful authentication to the Ubuntu host.

---

# Environment

## Management Workstation

- Operating system: Windows 11
- Windows account: `TWMGMT\brett`
- SSH implementation: OpenSSH for Windows 9.5p2
- SSH directory:

```text
C:\Users\brett\.ssh
```

- SSH configuration:

```text
C:\Users\brett\.ssh\config
```

## Remote System

- Host: `ubuntu-devops01`
- IP address: `192.168.1.114`
- Remote account: `brettcoder`
- Operating system: Ubuntu 24.04.5 LTS
- SSH server: OpenSSH 9.6p1
- SSH port: TCP/22

---

# Issue

VS Code Remote-SSH attempted to connect to:

```text
192.168.1.114
```

The VS Code connection failed before the VS Code Server installation or initialization process could begin.

The significant OpenSSH error was:

```text
Bad owner or permissions on C:\Users\brett\.ssh\config
```

A direct verbose SSH test reproduced the issue:

```powershell
ssh -v 192.168.1.114
```

Result:

```text
OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2

Bad permissions. Try removing permissions for user:
TWMGMT\admin
on file C:/Users/brett/.ssh/config.

Bad owner or permissions on C:\Users\brett/.ssh/config
```

This established that the failure was occurring in the **local Windows OpenSSH client**, not on the remote Ubuntu SSH server.

---

# Initial ACL Investigation

The ACL of the `.ssh` directory was examined:

```powershell
Get-Acl "$env:USERPROFILE\.ssh" |
    Format-List Owner,AccessToString
```

Result:

```text
Owner          : BUILTIN\Administrators

AccessToString :
NT AUTHORITY\SYSTEM Allow FullControl
BUILTIN\Administrators Allow FullControl
TWMGMT\brett Allow FullControl
TWMGMT\admin Allow FullControl
```

The SSH configuration file was then examined:

```powershell
Get-Acl "$env:USERPROFILE\.ssh\config" |
    Format-List Owner,AccessToString
```

Result:

```text
Owner          : TWMGMT\brett

AccessToString :
NT AUTHORITY\SYSTEM Allow FullControl
BUILTIN\Administrators Allow FullControl
TWMGMT\brett Allow FullControl
TWMGMT\admin Allow FullControl
```

The `config` file itself had the correct owner:

```text
TWMGMT\brett
```

However, another Windows account also had Full Control:

```text
TWMGMT\admin Allow FullControl
```

This became the primary suspect.

---

# Initial Remediation Attempt

An attempt was made to remove `TWMGMT\admin`:

```powershell
icacls "$env:USERPROFILE\.ssh\config" /remove "TWMGMT\admin"
```

The command reported:

```text
Successfully processed 1 files; Failed processing 0 files
```

However, verification showed:

```powershell
icacls "$env:USERPROFILE\.ssh\config"
```

Result:

```text
C:\Users\brett\.ssh\config
    NT AUTHORITY\SYSTEM:(I)(F)
    BUILTIN\Administrators:(I)(F)
    TWMGMT\brett:(I)(F)
    TWMGMT\admin:(I)(F)
```

The important indicator was:

```text
(I)
```

`(I)` indicates that the permission is **inherited**.

Therefore, the `TWMGMT\admin` ACE was not originating directly on the `config` file. It was being inherited from the parent directory.

This explains why `/remove` appeared to execute successfully while the unwanted permission remained effective.

---

# Root Cause

The effective ACL hierarchy was:

```text
C:\Users\brett\.ssh
│
│  TWMGMT\admin - Full Control
│
└── config
       │
       └── TWMGMT\admin - Inherited Full Control
```

The SSH `config` file inherited permissions from:

```text
C:\Users\brett\.ssh
```

Because `TWMGMT\admin` had Full Control on the parent directory, the same permission propagated to:

```text
C:\Users\brett\.ssh\config
```

Windows OpenSSH detected this and rejected the configuration file.

The failure therefore occurred locally before SSH authentication or VS Code Remote-SSH server initialization.

---

# Resolution

## Step 1 — Disable ACL Inheritance on the SSH Config

Inheritance was disabled while preserving the currently inherited permissions as explicit ACEs:

```powershell
icacls "$env:USERPROFILE\.ssh\config" /inheritance:d
```

Result:

```text
processed file: C:\Users\brett\.ssh\config
Successfully processed 1 files; Failed processing 0 files
```

Using `/inheritance:d` was important because it disabled future inheritance while converting the existing inherited entries into explicit entries.

This allowed individual ACEs to be removed safely.

---

## Step 2 — Remove the Unwanted Account

After inheritance was disabled:

```powershell
icacls "$env:USERPROFILE\.ssh\config" /remove "TWMGMT\admin"
```

Result:

```text
processed file: C:\Users\brett\.ssh\config
Successfully processed 1 files; Failed processing 0 files
```

---

## Step 3 — Verify the ACL

The resulting ACL was checked:

```powershell
icacls "$env:USERPROFILE\.ssh\config"
```

Result:

```text
C:\Users\brett\.ssh\config
    NT AUTHORITY\SYSTEM:(F)
    BUILTIN\Administrators:(F)
    TWMGMT\brett:(F)
```

The unwanted entry was gone:

```text
TWMGMT\admin
```

The `(I)` flags were also gone because the remaining ACEs were now explicit permissions on the file.

---

# Verification

A verbose SSH connection was attempted:

```powershell
ssh -v 192.168.1.114
```

OpenSSH successfully read the configuration:

```text
debug1: Reading configuration data C:\Users\brett/.ssh/config
debug1: C:\Users\brett/.ssh/config line 1: Applying options for 192.168.1.114
```

This was the first major confirmation that the ACL issue had been resolved.

Network connectivity was established:

```text
debug1: Connecting to 192.168.1.114 [192.168.1.114] port 22.
debug1: Connection established.
```

The SSH configuration correctly selected:

```text
brettcoder
```

as the remote account:

```text
debug1: Authenticating to 192.168.1.114:22 as 'brettcoder'
```

The remote host key was successfully validated against:

```text
C:\Users\brett\.ssh\known_hosts
```

The server permitted:

```text
publickey,password
```

authentication.

No usable local private key was present, so OpenSSH proceeded to password authentication:

```text
debug1: Next authentication method: password
```

Authentication succeeded:

```text
Authenticated to 192.168.1.114 ([192.168.1.114]:22) using "password".
```

The Ubuntu session successfully opened:

```text
Welcome to Ubuntu 24.04.5 LTS
(GNU/Linux 6.8.0-139-generic x86_64)
```

---

# Final State

The SSH configuration ACL was successfully repaired.

Final effective permissions:

```text
SYSTEM                 Full Control
BUILTIN\Administrators Full Control
TWMGMT\brett           Full Control
```

Removed:

```text
TWMGMT\admin
```

SSH successfully:

- Read the local SSH configuration
- Applied the host configuration
- Connected to TCP/22
- Validated the server host key
- Selected `brettcoder` as the remote user
- Authenticated using password authentication
- Established an interactive Ubuntu session

The original OpenSSH error was eliminated:

```text
Bad owner or permissions on C:\Users\brett\.ssh\config
```

---

# Troubleshooting Lessons

## 1. Test Outside VS Code

When VS Code Remote-SSH fails, testing with:

```powershell
ssh -v <host>
```

helps determine whether the problem belongs to:

```text
VS Code
    ↓
Local OpenSSH client
    ↓
Network
    ↓
Remote SSH server
    ↓
Authentication
```

In this case, `ssh -v` reproduced the problem independently of VS Code, immediately narrowing the investigation to Windows OpenSSH.

---

## 2. Successful `icacls` Execution Does Not Mean the Effective Permission Is Gone

This command:

```powershell
icacls "$env:USERPROFILE\.ssh\config" /remove "TWMGMT\admin"
```

reported success but did not eliminate the effective permission.

The reason was inheritance.

Always verify changes with:

```powershell
icacls <file>
```

rather than relying solely on the command's success message.

---

## 3. Recognize `(I)` in ICACLS Output

Example:

```text
TWMGMT\admin:(I)(F)
```

means:

```text
(I) = Inherited
(F) = Full Control
```

The `(I)` was the key diagnostic clue.

The permission had to be separated from the parent ACL before it could be removed from the file.

---

## 4. Avoid Removing SYSTEM or Administrators Without a Specific Reason

The remediation deliberately removed only:

```text
TWMGMT\admin
```

It did not blindly remove:

```text
NT AUTHORITY\SYSTEM
BUILTIN\Administrators
```

The troubleshooting principle was to make the **minimum necessary ACL change** and verify the result before modifying anything else.

---

## 5. The Failure Occurred Before Remote-Server Processing

Because Windows OpenSSH rejected:

```text
C:\Users\brett\.ssh\config
```

the original VS Code problem was not caused by:

- Ubuntu
- `sshd`
- VS Code Server
- Linux permissions
- TCP/22
- the Ubuntu firewall
- SSH host keys
- the remote `brettcoder` account

The local SSH client terminated before those layers became relevant.

---

# Additional Observation — Authentication Method

The verbose SSH output showed:

```text
identity file C:\Users\brett/.ssh/id_ed25519 type -1
```

and equivalent results for the other default private-key names.

The connection therefore fell back to:

```text
password
```

and succeeded.

This is not related to the ACL failure, but it establishes that this Windows workstation currently does not appear to be using one of the default local SSH private-key files for this host.

SSH key authentication can be configured separately later if desired.

---

# Command Reference

## `Get-Acl`

```powershell
Get-Acl "$env:USERPROFILE\.ssh"
```

### Purpose

Retrieves the Windows security descriptor for a file or directory.

### Why It Was Used

Used to inspect the owner and permissions assigned to the `.ssh` directory.

---

## `Format-List`

```powershell
Format-List Owner,AccessToString
```

### Purpose

Formats selected PowerShell object properties as a readable list.

### Parameters / Properties Used

`Owner`

Displays the security principal that owns the object.

`AccessToString`

Displays the object's access-control entries in human-readable form.

### Why It Was Used

Made the owner and effective ACL entries easy to inspect during troubleshooting.

---

## `$env:USERPROFILE`

```powershell
$env:USERPROFILE
```

### Purpose

References the current Windows user's profile directory.

For this workstation it resolves to:

```text
C:\Users\brett
```

### Why It Was Used

Avoids hard-coding the user's Windows profile path in commands.

---

## `icacls`

```powershell
icacls "$env:USERPROFILE\.ssh\config"
```

### Purpose

Displays or modifies NTFS discretionary access control lists.

### Why It Was Used

Provided detailed ACL information, including whether individual ACEs were inherited.

---

## `icacls /remove`

```powershell
icacls "$env:USERPROFILE\.ssh\config" /remove "TWMGMT\admin"
```

### Purpose

Removes ACEs associated with the specified security principal.

### Why It Was Used

Removed `TWMGMT\admin` from the SSH configuration after inheritance was disabled.

---

## `icacls /inheritance:d`

```powershell
icacls "$env:USERPROFILE\.ssh\config" /inheritance:d
```

### Purpose

Disables inheritance while copying inherited ACEs into explicit ACEs.

### Important Parameter

```text
/inheritance:d
```

Disables inheritance and preserves inherited permissions by converting them into explicit permissions.

### Why It Was Used

The unwanted `TWMGMT\admin` permission was inherited and therefore could not simply be removed while inheritance continued to supply it from the parent directory.

This command preserved the existing ACL while allowing the unwanted ACE to be removed individually.

---

## ICACLS `(I)`

Example:

```text
TWMGMT\admin:(I)(F)
```

### Meaning

```text
(I) = Inherited permission
(F) = Full Control
```

### Troubleshooting Significance

The `(I)` flag identified why the first `/remove` attempt did not eliminate the permission.

---

## `ssh -v`

```powershell
ssh -v 192.168.1.114
```

### Purpose

Starts an SSH connection with verbose diagnostic output.

### Parameter

```text
-v
```

Enables verbose logging.

Additional verbosity is available with:

```text
-vv
-vvv
```

### Why It Was Used

Allowed each stage of the SSH connection to be observed, including:

- Reading the SSH configuration
- Applying host options
- Establishing TCP connectivity
- SSH protocol negotiation
- Host-key validation
- Authentication-method selection
- Authentication
- Interactive-session creation

It also confirmed that the original ACL error had been eliminated.

---

# Resolution Summary

**Problem**

```text
Bad owner or permissions on C:\Users\brett\.ssh\config
```

**Cause**

`TWMGMT\admin` had inherited Full Control over the SSH configuration file.

**Key Diagnostic Evidence**

```text
TWMGMT\admin:(I)(F)
```

**Resolution**

```powershell
icacls "$env:USERPROFILE\.ssh\config" /inheritance:d
icacls "$env:USERPROFILE\.ssh\config" /remove "TWMGMT\admin"
icacls "$env:USERPROFILE\.ssh\config"
ssh -v 192.168.1.114
```

**Result**

```text
Authenticated to 192.168.1.114 ([192.168.1.114]:22) using "password".
```

SSH connectivity to `ubuntu-devops01` was restored, eliminating the local OpenSSH permissions failure that prevented VS Code Remote-SSH from connecting.