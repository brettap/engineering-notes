[CmdletBinding()]
param(
    [string]$ReportPath = (Join-Path $HOME 'Documents\TechWorks\SAM-012-Live\SAM-012-b60f3f1bc2fb4c16bb6346287953971e.json'),
    [string]$ModulePath = (Join-Path $PSScriptRoot '..\SAM012Audit.psm1')
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -lt [version]'7.0') {
    throw 'This diagnostic requires PowerShell 7 or later for case-colliding JSON keys.'
}
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "Report not found: $ReportPath"
}
if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
    throw "SAM-012 module not found: $ModulePath"
}

function Get-RecordValue {
    param($Record, [string]$Name)

    if ($null -eq $Record) { return $null }
    if ($Record -is [System.Collections.IDictionary]) { return $Record[$Name] }
    return $Record.$Name
}

function Get-SerializedEnumValue {
    param($Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $valueKey = @($Value.Keys | Where-Object { [string]$_ -ceq 'Value' } | Select-Object -First 1)
        if ($valueKey.Count -eq 0) {
            $valueKey = @($Value.Keys | Where-Object { [string]$_ -ieq 'Value' } | Select-Object -First 1)
        }
        if ($valueKey.Count -gt 0) { return $Value[$valueKey[0]] }
    }
    return $Value
}

$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json -AsHashtable
$checks = @($report.Checks | Where-Object { $_.CheckId -eq 'Techworks-DC01/Shares' })
if ($checks.Count -ne 1) { throw "Expected one Techworks-DC01/Shares check; found $($checks.Count)." }

$check = $checks[0]
$recognizedPrincipals = @('Everyone', 'NT AUTHORITY\Authenticated Users', 'TECHWORKS\Domain Computers')
$shareResults = foreach ($shareName in @('SYSVOL', 'NETLOGON')) {
    $shares = @($check.Evidence.Shares | Where-Object { $_.Name -eq $shareName })
    if ($shares.Count -ne 1) {
        [pscustomobject]@{ Name = $shareName; Error = "Expected one share record; found $($shares.Count)." }
        continue
    }

    $aces = foreach ($ace in @($shares[0].ShareAcl)) {
        $principal = Get-RecordValue $ace 'AccountName'
        $accessTypeRaw = Get-RecordValue $ace 'AccessControlType'
        $accessRightRaw = Get-RecordValue $ace 'AccessRight'
        $accessType = Get-SerializedEnumValue $accessTypeRaw
        $accessRight = Get-SerializedEnumValue $accessRightRaw
        $principalRecognized = $principal -in $recognizedPrincipals

        [pscustomobject]@{
            Principal = $principal
            PrincipalRecognizedByEvaluator = $principalRecognized
            AccessControlTypeRaw = $accessTypeRaw
            AccessType = $accessType
            AccessRightRaw = $accessRightRaw
            AccessRight = $accessRight
            CurrentEvaluatorRecognizesGrant = ($accessTypeRaw -eq 'Allow' -and $principalRecognized)
            AfterEnumValueNormalizationRecognizesGrant = ($accessType -eq 'Allow' -and $principalRecognized)
        }
    }

    [pscustomobject]@{ Name = $shareName; Aces = @($aces) }
}

$sourceMatch = Select-String -LiteralPath $ModulePath -Pattern "AccessControlType -eq 'Allow'" |
    Select-Object -First 1

[pscustomobject]@{
    Diagnostic = 'SAM-012 SYSVOL/NETLOGON share ACL false-positive analysis'
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    AuditRunId = $report.RunId
    CheckId = $check.CheckId
    CheckStatus = $check.Status
    CheckFindings = @($check.Findings)
    Shares = @($shareResults)
    EvaluatorSource = if ($null -eq $sourceMatch) { $null } else {
        [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $ModulePath).Path; Line = $sourceMatch.LineNumber; Code = $sourceMatch.Line.Trim() }
    }
    Interpretation = 'The current evaluator matches AccountName and AccessControlType directly. A serialized enum object does not equal its Value string; this diagnostic unwraps Value only for comparison. AccessRight is reported but is not part of the current grant predicate.'
    ScopeLimit = 'Share ACL recognition only. This does not establish NTFS effective access or ordinary-user access to either share.'
} | ConvertTo-Json -Depth 12