#requires -Version 5.1
<#
.SYNOPSIS
SAM-012 read-only AD audit. Live collection requires explicit -Live.
.DESCRIPTION
Fixture mode never imports Windows modules or invokes remote collectors.
Reports are written only beneath the supplied local OutputDirectory.
#>
[CmdletBinding(DefaultParameterSetName = 'Fixture')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Live')][switch]$Live,
    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')][string]$FixturePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string[]]$Clients = @(),
    [System.Management.Automation.PSCredential]$Credential,
    [System.Management.Automation.PSCredential]$UserReadCredential,
    [string]$MachineEvidencePath,
    [ValidateRange(1, 168)][int]$EventLookbackHours = 24,
    [ValidateRange(1, 10000)][int]$MaxEventsPerLog = 200,
    [ValidateRange(1, 3600)][int]$CheckTimeoutSeconds = 30,
    [ValidateRange(1, 3600)][int]$EventTimeoutSeconds = 60,
    [ValidateRange(1, 86400)][int]$OverallTimeoutSeconds = 600,
    [ValidateRange(1, 10080)][int]$ReplicationWarnMinutes = 60,
    [ValidateRange(1, 10080)][int]$SyncWarnMinutes = 120,
    [ValidateRange(0.001, 300)][double]$OffsetWarnSeconds = 1,
    [ValidateRange(0.001, 300)][double]$OffsetFailSeconds = 5,
    [ValidateRange(1, 168)][int]$EvidenceMaxAgeHours = 24,
    [string[]]$ApprovedTimePeers = @('time.windows.com', 'time.nist.gov'),
    [string]$ExpectedTimeZone = 'Eastern Standard Time'
)
Import-Module (Join-Path $PSScriptRoot 'SAM012Audit.psm1') -Force -ErrorAction Stop
$arguments = @{}
foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
Invoke-SAM012Audit @arguments
