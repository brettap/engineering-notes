# SAM-004 — Setting Up GPO for RDP

**Document name:** `SAM-004-setting-up-gpo-for-rdp.md`

## Synopsis

### Issue

The TechWorks Active Directory lab had two domain controllers and multiple Windows 11 domain clients, but centralized administrative access to the client systems had not been established.

The normal domain account `TECHWORKS\techwork` could successfully authenticate to the clients but could not elevate through UAC because it was not a local administrator. Rather than granting the everyday account excessive domain or forest privileges, a separate administrative account and security group were implemented.

The workstation computer objects were also located in the default `Computers` container, which did not provide the desired OU-based Group Policy scope.

### Intended Result

Establish a least-privilege remote workstation administration model that:

- Keeps `techwork` as a standard domain user.
- Uses `techwork-admin` for workstation administration.
- Uses the `Workstation-Admins` AD security group to assign administrative rights.
- Places managed clients in a dedicated `Workstations` OU.
- Uses Group Policy to grant workstation administrative access.
- Enables Remote Desktop centrally for managed workstations.
- Provides successful RDP access to multiple Windows clients without granting unnecessary Domain Admin or Enterprise Admin privileges.

---

## Environment

**Active Directory domain:** `techworks.local`

**NetBIOS domain:** `TECHWORKS`

**Domain Controllers:**

```text
TECHWORKS-DC01
DC-02
```

**Managed workstation OU:**

```text
OU=Workstations,DC=techworks,DC=local
```

**Workstations moved into the OU:**

```text
TW-CL00
TW-CL01
TW-CL02
```

**Standard account:**

```text
TECHWORKS\techwork
```

**Administrative account:**

```text
TECHWORKS\techwork-admin
```

**Administrative security group:**

```text
TECHWORKS\Workstation-Admins
```

**Final GPO name:**

```text
GPO-Workstation-Remote-Administration
```

---

# 1. Initial Problem Discovery

The `techwork` account successfully authenticated to TW-CL00:

```cmd
whoami
```

Result:

```text
techworks\techwork
```

The workstation identity was verified:

```cmd
hostname
```

Result:

```text
TW-CL00
```

However, attempting to perform an administrative operation generated a UAC credential prompt rather than allowing elevation.

This demonstrated that successful **domain authentication** did not mean that the user possessed **local administrative authorization** on the workstation.

---

# 2. AD Account Verification

The domain account was checked from DC01:

```powershell
Get-ADUser techwork -Properties Enabled,LockedOut,PasswordExpired,PasswordLastSet |
    Select-Object SamAccountName,UserPrincipalName,Enabled,LockedOut,PasswordExpired,PasswordLastSet
```

The account was:

- Enabled.
- Not locked out.
- Not password-expired.

The domain configuration was also verified:

```powershell
Get-ADDomain |
    Format-List DNSRoot,NetBIOSName
```

Result:

```text
DNSRoot     : techworks.local
NetBIOSName : TECHWORKS
```

The UPN initially appeared in copied output as:

```text
techwork\@techworks.local
```

Rather than modifying the account based on presentation alone, the underlying characters were inspected:

```powershell
(Get-ADUser techwork -Properties UserPrincipalName).UserPrincipalName.ToCharArray() |
    ForEach-Object { "'$_' = $([int][char]$_)" }
```

The sequence showed:

```text
'k' = 107
'@' = 64
't' = 116
```

This proved that the actual AD value was correctly stored as:

```text
techwork@techworks.local
```

No UPN correction was required.

---

# 3. AD Replication Verification

Because two domain controllers were present, replication was explicitly synchronized and verified:

```cmd
repadmin /syncall /AdeP
```

Replication completed successfully for all naming contexts, including:

```text
ForestDnsZones
DomainDnsZones
Schema
Configuration
techworks.local
```

The account was then queried specifically against DC02:

```powershell
Get-ADUser techwork -Server DC-02 -Properties UserPrincipalName |
    Format-List SamAccountName,UserPrincipalName
```

This confirmed that DC02 contained the replicated account information.

---

# 4. Least-Privilege Administrative Design

An initial possibility was to add the normal user to privileged groups such as:

```text
Domain Admins
Enterprise Admins
```

This was intentionally avoided.

Those privileges were unnecessary for workstation administration and would violate the principle of least privilege.

Instead, administrative duties were separated from everyday user activity.

The resulting model became:

```text
TECHWORKS\techwork
    |
    +-- Standard domain user


TECHWORKS\techwork-admin
    |
    +-- Workstation-Admins
             |
             +-- Local Administrators on managed workstations
```

This provides separate credentials for privileged administrative operations.

---

# 5. Workstation-Admins Security Group

The AD security group was created as:

```text
Workstation-Admins
```

The administrative account was added:

```text
techwork-admin
```

Membership was verified:

```powershell
Get-ADGroupMember "Workstation-Admins" |
    Select-Object Name,SamAccountName,ObjectClass
```

Result:

```text
Name             SamAccountName    ObjectClass
----             --------------    -----------
techworks admin  techwork-admin    user
```

The normal `techwork` account was intentionally not added.

---

# 6. Workstations OU

The client computer accounts initially existed inside the default:

```text
CN=Computers
```

container.

A dedicated Organizational Unit was created:

```text
Workstations
```

The managed workstation computer objects were moved into it:

```text
TW-CL00
TW-CL01
TW-CL02
```

The placement was verified with:

```powershell
Get-ADComputer TW-CL00 |
    Select-Object Name,DistinguishedName
```

Result:

```text
Name    DistinguishedName
----    -----------------
TW-CL00 CN=TW-CL00,OU=Workstations,DC=techworks,DC=local
```

This established a clean Group Policy scope for workstation-specific configuration without applying those settings to the domain controllers.

---

# 7. OU and GPO Architecture

An important distinction was demonstrated during the implementation.

The OUs created in Active Directory Users and Computers automatically appeared in Group Policy Management because GPMC displays the domain's existing Active Directory OU hierarchy.

For example:

```text
techworks.local
│
├── Accounting
├── Domain Controllers
├── HR
├── Techworks Users
└── Workstations
```

These are **not automatically created GPOs**.

They are the existing AD OUs to which GPOs can be linked.

The actual GPO objects are stored separately beneath:

```text
Group Policy Objects
```

Therefore:

```text
OU
    = organizational/policy scope

Security Group
    = authorization/membership

GPO
    = configuration policy

GPO Link
    = associates a GPO with an AD scope
```

---

# 8. Workstation Administration GPO

A new GPO was created and linked directly to the `Workstations` OU.

The initial name was:

```text
GPO-Workstation-Local-Admins
```

As its responsibilities expanded to include RDP configuration, it was renamed:

```text
GPO-Workstation-Remote-Administration
```

The resulting structure was:

```text
techworks.local
│
└── Workstations
    │
    ├── TW-CL00
    ├── TW-CL01
    ├── TW-CL02
    │
    └── GPO Link:
        GPO-Workstation-Remote-Administration
```

The policy was intentionally linked at the **Workstations OU**, rather than the domain root, to prevent workstation-specific administrative configuration from applying to DC01/DC02.

---

# 9. Deploying Local Administrator Membership

The GPO was edited at:

```text
Computer Configuration
└── Preferences
    └── Control Panel Settings
        └── Local Users and Groups
```

A **Local Group** preference was created.

Configuration:

```text
Action:
Update

Group:
Administrators (built-in)

Member:
TECHWORKS\Workstation-Admins

Member Action:
ADD
```

The following options remained unchecked:

```text
Delete all member users
Delete all member groups
```

This was important because the objective was to **add** the domain administrative group without replacing existing local administrator membership.

The resulting model was:

```text
TW-CL00\Administrators
│
├── Existing administrative principals
│
└── TECHWORKS\Workstation-Admins
        │
        └── TECHWORKS\techwork-admin
```

The same policy applies to the other computer objects located in the Workstations OU.

---

# 10. Group Policy Deployment

On the client workstation, Group Policy was refreshed:

```cmd
gpupdate /force
```

The workstation was rebooted during testing.

An important observation occurred on another client: rebooting alone did not result in the expected administrative access immediately.

Running:

```cmd
gpupdate /force
```

after the reboot caused the new policy to apply successfully.

This demonstrated that simply configuring and linking a GPO does not mean a client has necessarily processed the new policy yet.

---

# 11. Administrative Elevation Test

The workstation remained logged in using the standard account:

```text
TECHWORKS\techwork
```

An administrative process was launched.

When UAC requested administrative credentials, the separate privileged account was supplied:

```text
TECHWORKS\techwork-admin
```

The elevation succeeded.

This confirmed that the GPO successfully made:

```text
TECHWORKS\Workstation-Admins
```

a member of the workstation's local:

```text
BUILTIN\Administrators
```

without requiring the standard `techwork` account to receive administrative privileges.

---

# 12. Remote Desktop Deployment

The workstation administration GPO was subsequently used to enable Remote Desktop for the managed workstation scope.

The Windows Firewall was verified not to be blocking the required RDP communication.

Remote Desktop access was successfully established to **two separate workstation clients**.

This provided an important multi-client validation:

```text
Central AD/GPO configuration
           |
           v
Workstations OU
           |
      +----+----+
      |         |
      v         v
   Client 1   Client 2
      |         |
      +----+----+
           |
     RDP successful
```

No per-client manual assignment of the domain administrative group was required.

---

# 13. Final Administrative Model

The resulting TechWorks workstation-management architecture is:

```text
techworks.local
│
├── Domain Controllers
│   ├── TECHWORKS-DC01
│   └── DC-02
│
├── Workstations
│   ├── TW-CL00
│   ├── TW-CL01
│   └── TW-CL02
│
└── Security Groups
    └── Workstation-Admins
        └── techwork-admin
```

with:

```text
GPO-Workstation-Remote-Administration
              |
              v
        Workstations OU
              |
              +-- Workstation-Admins
              |       ↓
              |   Local Administrators
              |
              +-- Remote Desktop enabled
```

The standard account remains:

```text
TECHWORKS\techwork
```

while privileged workstation administration uses:

```text
TECHWORKS\techwork-admin
```

---

# Problems Encountered

### UAC elevation failure

`techwork` could authenticate to TW-CL00 but could not elevate because domain authentication and local administrative authorization are separate concepts.

**Resolution:** A dedicated workstation-administration model was implemented instead of elevating the everyday account.

### Apparent malformed UPN

PowerShell/copied output appeared to show:

```text
techwork\@techworks.local
```

Character-level inspection proved the actual stored UPN contained `@` directly and was valid.

**Resolution:** No unnecessary AD modification was performed.

### Incorrect understanding of OU/security-group placement

During the exercise, computer organization and security-group membership were initially conflated.

**Resolution:** TW-CL00/01/02 were placed in the `Workstations` **OU**, while `techwork-admin` was placed in the `Workstation-Admins` **security group**.

### Policy not immediately effective after reboot

One client required:

```cmd
gpupdate /force
```

after reboot before the newly configured policy took effect.

**Resolution:** A forced Group Policy refresh was performed and administrative access succeeded.

---

# Lessons Learned

**Authentication is not authorization.** A domain user being able to sign into a workstation does not mean that account possesses local administrator privileges.

**OU and security-group membership serve different purposes.** OUs organize AD objects and provide Group Policy/delegation scope; security groups are used primarily to assign permissions and authorization.

**GPOs and OUs are separate objects.** GPMC displays the AD OU hierarchy because those OUs are valid GPO link targets. The actual GPO remains an independent object.

**Least privilege is preferable to convenience.** Workstation administration did not require granting the everyday account Domain Admin or Enterprise Admin privileges.

**Administrative accounts should be separated from normal accounts.** `techwork` remains the daily account while `techwork-admin` is used when elevation is required.

**Group Policy provides scalable administration.** Instead of manually configuring local administrator membership and RDP independently on every workstation, the configuration can be centrally controlled through AD and GPO.

**Verify before modifying.** The apparent UPN issue demonstrated why raw values should be validated before changing production-like directory objects.

---

# Command Reference

### `whoami`

```cmd
whoami
```

Displays the security principal associated with the current logon session.

**Why used:** Confirmed whether the workstation session was running as the expected domain account.

---

### `hostname`

```cmd
hostname
```

Displays the local computer's hostname.

**Why used:** Confirmed which workstation was being administered during testing.

---

### `Get-ADUser`

```powershell
Get-ADUser techwork -Properties Enabled,LockedOut,PasswordExpired,PasswordLastSet
```

Retrieves an Active Directory user.

**Important parameters:**

`techwork` — identifies the account being queried.

`-Properties` — requests additional AD attributes that are not returned in the default property set.

**Why used:** Verified that the account was enabled, unlocked and had a valid password state.

---

### `Get-ADDomain`

```powershell
Get-ADDomain |
    Format-List DNSRoot,NetBIOSName
```

Retrieves information about the current Active Directory domain.

**Why used:** Verified both:

```text
techworks.local
TECHWORKS
```

which clarified the proper domain logon formats.

---

### `ToCharArray()`

```powershell
(Get-ADUser techwork -Properties UserPrincipalName).UserPrincipalName.ToCharArray()
```

Converts the UPN string into individual characters.

Combined with:

```powershell
ForEach-Object { "'$_' = $([int][char]$_)" }
```

it displays each character and its numeric character value.

**Why used:** Proved that the UPN contained a genuine `@` character (`64`) rather than a stored backslash.

---

### `repadmin /syncall /AdeP`

```cmd
repadmin /syncall /AdeP
```

Forces Active Directory replication synchronization.

**Important switches:**

`/A` — synchronizes all naming contexts held by the target DC.

`/d` — identifies servers using distinguished names in messages.

`/e` — includes domain controllers across sites.

`/P` — pushes changes outward from the specified DC.

**Why used:** Verified/synchronized AD information between DC01 and DC02 before continuing authentication troubleshooting.

---

### `Get-ADUser -Server`

```powershell
Get-ADUser techwork -Server DC-02 -Properties UserPrincipalName
```

Queries a specific domain controller rather than allowing normal DC discovery to select one.

**Important parameter:**

`-Server DC-02` — directs the request specifically to DC02.

**Why used:** Confirmed that replicated account information was present on the second domain controller.

---

### `Get-ADGroupMember`

```powershell
Get-ADGroupMember "Workstation-Admins" |
    Select-Object Name,SamAccountName,ObjectClass
```

Lists members of an Active Directory group.

**Why used:** Verified that `techwork-admin` was a member of `Workstation-Admins`.

---

### `Get-ADComputer`

```powershell
Get-ADComputer TW-CL00 |
    Select-Object Name,DistinguishedName
```

Retrieves an Active Directory computer object.

**Why used:** Verified that TW-CL00 had been moved from the default `Computers` container into:

```text
OU=Workstations,DC=techworks,DC=local
```

---

### `gpupdate /force`

```cmd
gpupdate /force
```

Forces Windows to refresh Group Policy.

**Important switch:**

`/force` — reapplies all applicable policy settings rather than only settings Windows determines have changed.

**Why used:** Forced the workstations to process the newly linked/configured workstation GPO during validation.

---

## SAM-004 Result

**Status: SUCCESS**

The TechWorks domain now has a centrally managed workstation-administration model using:

```text
Dedicated Workstations OU
        +
Dedicated administrative account
        +
Workstation-Admins security group
        +
Group Policy
        +
Local administrator delegation
        +
Remote Desktop
```

RDP access was successfully established to multiple domain workstations while preserving separation between the everyday `techwork` account and the privileged `techwork-admin` account.