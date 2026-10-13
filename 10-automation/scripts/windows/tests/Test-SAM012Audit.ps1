#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('sam012-tests-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../SAM012Audit.psm1') -Force
. (Join-Path $PSScriptRoot 'fixtures/Healthy-SAM012.ps1')
$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$script:passed = 0
function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Get-Evidence { param($Fixture, $Id); ($Fixture.Checks | Where-Object { $_.CheckId -eq $Id }).Result.Evidence }
function Run-Case {
    param([string]$Name, [scriptblock]$Mutate, [scriptblock]$Assert, [hashtable]$Options = @{})
    $f = New-SAM012HealthyFixture
    if ($null -ne $Mutate) { & $Mutate $f }
    $path = Join-Path $OutputDirectory ($Name + '.fixture.json')
    $f | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
    $result = Invoke-SAM012Audit -FixturePath $path -OutputDirectory $OutputDirectory @Options
    & $Assert $result.Report $result.Paths
    $script:passed++
    Write-Output ('PASS ' + $Name)
}
function Find-Check { param($Report, $Id); $Report.Checks | Where-Object { $_.CheckId -eq $Id } }
function Assert-SAM012HtmlEvidence {
    param([string]$Html, [string]$ExpectedMessage)
    $blocks = [regex]::Matches($Html, '<pre>([\s\S]*?)</pre>')
    Assert-True ($blocks.Count -eq 1) 'Expected one HTML evidence block.'
    $encoded = $blocks[0].Groups[1].Value
    $json = [Net.WebUtility]::HtmlDecode($encoded)
    # Check HTML encoding independently of the JSON serializer's escape style.
    Assert-True ($encoded -ceq [Net.WebUtility]::HtmlEncode($json)) 'Event HTML was not escaped.'
    $decoded = $json | ConvertFrom-Json
    $event = (Find-Check $decoded 'DC-02/Events:System').Evidence.Events[0]
    Assert-True ($event.Message -ceq $ExpectedMessage) 'HTML evidence did not preserve the event message.'
}
function New-SAM012SerializedEnum {
    param([string]$Name)
    $number = 0
    if ($Name -eq 'Deny') { $number = 1 }
    $value = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $value.Add('value', $number)
    $value.Add('Value', $Name)
    return ,$value
}
function Get-SAM012ShareEvaluation {
    param([object[]]$Aces)
    $shares = @(
        [pscustomobject]@{ Name = 'SYSVOL'; Sddl = 'O:SYG:SYD:(A;;FR;;;AU)'; ShareAcl = @($Aces); Policy = [pscustomobject]@{ Sddl = 'O:SYG:SYD:(A;;FR;;;AU)' } }
        [pscustomobject]@{ Name = 'NETLOGON'; Sddl = 'O:SYG:SYD:(A;;FR;;;AU)'; ShareAcl = @($Aces); Policy = $null }
    )
    Test-SAM012Evidence -Kind 'Shares' -Evidence ([pscustomobject]@{ Shares = $shares }) `
        -Target ([pscustomobject]@{ Name = 'Techworks-DC01' }) -Options @{} -NowUtc ([datetime]::UtcNow)
}

# AST syntax check and mutating-command boundary, including embedded collectors.
$modulePath = Join-Path $PSScriptRoot '../SAM012Audit.psm1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Module parse errors.'
$commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
foreach ($forbidden in @('Restart-Service', 'Restart-Computer', 'Set-Service', 'Set-ADObject', 'Invoke-GPUpdate', 'Register-ScheduledTask',
    'Start-ScheduledTask', 'Enable-PSRemoting', 'Grant-SmbShareAccess', 'Clear-DnsClientCache', 'dcdiag', 'repadmin', 'nltest', 'gpupdate', 'Invoke-Expression')) {
    Assert-True ($commands -notcontains $forbidden) "Forbidden command: $forbidden"
}
Assert-True ((Get-Content $modulePath -Raw) -notmatch '/resync|/syncall|/DnsDynamicUpdate') 'Mutating native switch present.'
$script:passed++; Write-Output 'PASS syntax-and-read-only-boundary'

# Guard against accidental live collection in every fixture scenario.
$module = Get-Module SAM012Audit
& $module { function script:Invoke-SAM012Bounded { throw 'Fixture mode attempted live collection.' } }

Run-Case 'healthy-and-reports' $null {
    param($r, $p)
    Assert-True $r.Summary.HealthyAndComplete 'Healthy fixture did not pass.'
    Assert-True ($r.Summary.MandatoryChecks -eq 27 -and $r.Summary.OptionalChecks -eq 0) 'Scope counts wrong.'
    $json = Get-Content $p.Json -Raw | ConvertFrom-Json
    $csv = @(Import-Csv $p.Csv)
    Assert-True ($json.Checks.Count -eq 27 -and $csv.Count -eq 27) 'Report round-trip mismatch.'
    Assert-True ((Get-Content $p.Html -Raw) -match 'Full evidence and errors') 'HTML evidence missing.'
}
Run-Case 'dc01-unreachable' {
    param($f)
    ($f.Checks | Where-Object { $_.CheckId -eq 'Techworks-DC01/Identity' }).Result = @{ Success = $false; Evidence = $null
        Error = @{ Category = 'ConnectionError'; Message = 'Synthetic unreachable'; Id = 'Fixture.Unreachable' } }
} {
    param($r)
    Assert-True (-not $r.Summary.HealthyAndComplete) 'Unreachable DC passed.'
    Assert-True ((Find-Check $r 'DC-02/Identity').Status -eq 'PASS') 'DC02 not independently checked.'
    Assert-True ((Find-Check $r 'Techworks-DC01/Replication').Error.Category -eq 'Dependency') 'Dependency not identified.'
}
Run-Case 'wrong-target' { param($f); (Get-Evidence $f 'Techworks-DC01/Identity').Hostname = 'OTHER' } {
    param($r); Assert-True ((Find-Check $r 'Techworks-DC01/Identity').Status -eq 'FAIL') 'Wrong host passed.'
    Assert-True ((Find-Check $r 'Techworks-DC01/Shares').Error.Category -eq 'Dependency') 'Wrong-host collection not gated.'
}
Run-Case 'sam002-acl-and-machine' {
    param($f)
    (Get-Evidence $f 'Techworks-DC01/Shares').Shares[0].ShareAcl = @(@{ AccountName = 'BUILTIN\Administrators'; AccessControlType = 'Allow'; AccessRight = 'Full' })
    (Get-Evidence $f 'Techworks-DC01/MachineRead').Reads[0].Readable = $false
} {
    param($r); Assert-True ((Find-Check $r 'Techworks-DC01/Shares').Status -eq 'FAIL') 'Admin-only ACL passed.'
    Assert-True ((Find-Check $r 'Techworks-DC01/MachineRead').Status -eq 'FAIL') 'Machine failure masked.'
}
$recognizedPrincipals = @('Everyone', 'NT AUTHORITY\Authenticated Users', 'TECHWORKS\Domain Computers')
foreach ($principal in $recognizedPrincipals) {
    $plainStringResult = Get-SAM012ShareEvaluation -Aces @(@{ AccountName = $principal; AccessControlType = 'Allow'; AccessRight = 'Read' })
    Assert-True ($plainStringResult.Status -eq 'PASS') "Plain-string grant for $principal was rejected."
}
$script:passed++; Write-Output 'PASS share-plain-string-recognized-principals'
$nestedAllowResult = Get-SAM012ShareEvaluation -Aces @(@{ AccountName = 'Everyone'; AccessControlType = (New-SAM012SerializedEnum 'Allow'); AccessRight = 'Read' })
Assert-True ($nestedAllowResult.Status -eq 'PASS') 'Nested enum Allow grant was rejected.'
$script:passed++; Write-Output 'PASS share-nested-enum-allow'
$nestedDenyResult = Get-SAM012ShareEvaluation -Aces @(@{ AccountName = 'Everyone'; AccessControlType = (New-SAM012SerializedEnum 'Deny'); AccessRight = 'Read' })
Assert-True ($nestedDenyResult.Status -eq 'FAIL') 'Deny-only share ACE passed as an ordinary-client grant.'
Assert-True (@($nestedDenyResult.Findings | Where-Object { $_ -like '*has deny ACEs*' }).Count -eq 2) 'Nested enum deny ACE warning was missed.'
$script:passed++; Write-Output 'PASS share-nested-enum-deny'
$mixedDenyResult = Get-SAM012ShareEvaluation -Aces @(
    @{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Read' }
    @{ AccountName = 'Everyone'; AccessControlType = (New-SAM012SerializedEnum 'Deny'); AccessRight = 'Read' }
)
Assert-True ($mixedDenyResult.Status -eq 'WARN') 'Deny ACE did not warn when a recognized allow grant was present.'
$script:passed++; Write-Output 'PASS share-allow-with-deny-warning'
$adminOnlyResult = Get-SAM012ShareEvaluation -Aces @(@{ AccountName = 'BUILTIN\Administrators'; AccessControlType = (New-SAM012SerializedEnum 'Allow'); AccessRight = 'Full' })
Assert-True ($adminOnlyResult.Status -eq 'FAIL') 'Nested enum administrator-only ACL passed.'
$script:passed++; Write-Output 'PASS share-nested-enum-admin-only'
Run-Case 'ordinary-user-denied' { param($f); (Get-Evidence $f 'Techworks-DC01/UserRead').Reads[0].Readable = $false } {
    param($r); Assert-True ((Find-Check $r 'Techworks-DC01/UserRead').Status -eq 'FAIL') 'User denial masked.'
}
Run-Case 'missing-machine-evidence' { param($f); $f.Checks = @($f.Checks | Where-Object { $_.CheckId -ne 'DC-02/MachineRead' }) } {
    param($r); Assert-True ((Find-Check $r 'DC-02/MachineRead').Status -eq 'UNKNOWN') 'Missing machine evidence passed.'
    Assert-True ($r.Summary.Completeness -eq 'INCOMPLETE') 'Missing evidence completeness wrong.'
}
Run-Case 'stale-machine-evidence' { param($f); (Get-Evidence $f 'DC-02/MachineRead').TimestampUtc = '2026-10-01T00:00:00Z' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/MachineRead').Status -eq 'UNKNOWN') 'Stale machine evidence passed.'
}
Run-Case 'sam003-client-only-warning' { param($f); (Get-Evidence $f 'TW-CL01/ClientDNS').Interfaces[0].ServerAddresses = @('192.168.1.51') } {
    param($r); Assert-True ((Find-Check $r 'TW-CL01/ClientDNS').Status -eq 'WARN') 'Single resolver not flagged.'
    Assert-True $r.Summary.HealthyAndComplete 'Optional failure changed mandatory health.'
    Assert-True ($r.Summary.OptionalChecks -eq 2) 'Optional checks missing.'
} @{ Clients = @('TW-CL01') }
Run-Case 'replication-failed' { param($f); (Get-Evidence $f 'DC-02/Replication').Partners[0].LastReplicationResult = 1722 } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Replication').Status -eq 'FAIL') 'Replication failure passed.'
}
Run-Case 'replication-missing-partition' { param($f); $e = Get-Evidence $f 'DC-02/Replication'; $e.Partners = @($e.Partners | Select-Object -Skip 1) } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Replication').Status -eq 'UNKNOWN') 'Partition gap passed.'
}
Run-Case 'replication-threshold' { param($f); (Get-Evidence $f 'DC-02/Replication').Partners[0].LastReplicationSuccess = '2026-10-13T15:45:00Z' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Replication').Status -eq 'WARN') 'Configured replication threshold ignored.'
} @{ ReplicationWarnMinutes = 10 }
Run-Case 'sam011-free-running' { param($f); $e = Get-Evidence $f 'Techworks-DC01/Time'; $e.Source = 'Free-running System Clock'; $e.Type = 'NT5DS' } {
    param($r); Assert-True ((Find-Check $r 'Techworks-DC01/Time').Status -eq 'FAIL') 'Free-running PDC passed.'
    Assert-True ((Find-Check $r 'Techworks-DC01/Services').Status -eq 'PASS') 'Time failure fabricated service failure.'
}
Run-Case 'localized-time' { param($f); (Get-Evidence $f 'DC-02/Time').ParseSuccess = $false } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Time').Status -eq 'UNKNOWN') 'Unparsed time passed.'
}
Run-Case 'offset-threshold' { param($f); (Get-Evidence $f 'DC-02/Offset').Samples = @(2, 2, 2, 2, 2) } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Offset').Status -eq 'FAIL') 'Offset threshold ignored.'
} @{ OffsetWarnSeconds = 0.5; OffsetFailSeconds = 1.5 }
Run-Case 'offset-partial' { param($f); (Get-Evidence $f 'DC-02/Offset').Samples = @(0.1) } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Offset').Status -eq 'UNKNOWN') 'Partial samples passed.'
}
Run-Case 'dns-srv-missing' { param($f); (Get-Evidence $f 'DC-02/DNS').Answers[3].Values = @('DC-02.techworks.local') } {
    param($r); Assert-True ((Find-Check $r 'DC-02/DNS').Status -eq 'FAIL') 'Missing DC SRV passed.'
}
Run-Case 'service-stopped' { param($f); (Get-Evidence $f 'DC-02/Services').Services[0].Status = 'Stopped' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Services').Status -eq 'FAIL') 'Stopped NTDS passed.'
}
Run-Case 'permission-error' {
    param($f); ($f.Checks | Where-Object { $_.CheckId -eq 'DC-02/Shares' }).Result = @{ Success = $false; Evidence = $null
        Error = @{ Category = 'PermissionDenied'; Message = 'Synthetic access denied'; Id = 'Fixture.Denied' } }
} { param($r); Assert-True ((Find-Check $r 'DC-02/Shares').Error.Category -eq 'PermissionDenied') 'Permission error lost.' }
Run-Case 'events-truncated-and-wrong-host' {
    param($f); $e = Get-Evidence $f 'DC-02/Events:System'; $e.Truncated = $true
    $e.Events = @(@{ Computer = 'TW-CL01'; Provider = 'Microsoft-Windows-Time-Service'; Id = 36; Level = 3; Message = 'Synthetic'; Xml = '<Event/>' })
} { param($r); Assert-True ((Find-Check $r 'DC-02/Events:System').Status -eq 'UNKNOWN') 'Event gaps passed.' }
Run-Case 'events-html-escape' {
    param($f); (Get-Evidence $f 'DC-02/Events:System').Events = @(@{ Computer = 'DC-02'; Provider = 'Microsoft-Windows-Time-Service'
        Id = 36; Level = 3; Message = '<script>alert("fixture")</script>'; Xml = '<Event/>' })
} {
    param($r, $p); $html = Get-Content $p.Html -Raw
    Assert-SAM012HtmlEvidence $html '<script>alert("fixture")</script>'
    Assert-True ((Find-Check $r 'DC-02/Events:System').Status -eq 'WARN') 'Historical event not flagged.'
}
Run-Case 'html-special-characters' {
    param($f); (Get-Evidence $f 'DC-02/Events:System').Events = @(@{ Computer = 'DC-02'
        Provider = 'fixture<&>"''provider'; Id = 36; Level = 3
        Message = '</pre><script>alert("fixture")</script> & ''single'' "double" &lt; literal \u003c'; Xml = '<Event/>' })
} {
    param($r, $p)
    $html = Get-Content $p.Html -Raw
    $check = Find-Check $r 'DC-02/Events:System'
    Assert-SAM012HtmlEvidence $html $check.Evidence.Events[0].Message
    # Findings bypass JSON serialization, so exercise direct HTML text encoding too.
    $finding = [Net.WebUtility]::HtmlEncode(($check.Findings -join '; '))
    Assert-True ($html.Contains('<td>' + $finding + '</td>')) 'HTML findings did not encode special characters.'
    Assert-True ($html -notmatch '<script\b') 'Event markup escaped its text container.'
}
Run-Case 'html-windows51-json-escapes' {
    param($f); (Get-Evidence $f 'DC-02/Events:System').Events = @(@{ Computer = 'DC-02'
        Provider = 'fixture'; Id = 36; Level = 3; Message = '<script> & ''single'' "double" </script>'; Xml = '<Event/>' })
} {
    param($r, $p)
    # Reproduce Desktop JSON Unicode escapes locally without requiring Windows.
    # PowerShell 5.1 has no ConvertTo-Json -EscapeHandling parameter.
    $json = Get-Content $p.Json -Raw
    $desktopJson = $json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026').Replace("'", '\u0027')
    $html = '<pre>' + [Net.WebUtility]::HtmlEncode($desktopJson) + '</pre>'
    Assert-True ($html -notmatch '&lt;script&gt;') 'Fixture did not reproduce the original false failure.'
    Assert-SAM012HtmlEvidence $html '<script> & ''single'' "double" </script>'
    # Negative control: removing HTML encoding must still fail the corrected test.
    $rejected = $false
    try { Assert-SAM012HtmlEvidence ('<pre>' + $desktopJson + '</pre>') '<script> & ''single'' "double" </script>' }
    catch { $rejected = $_.Exception.Message -eq 'Event HTML was not escaped.' }
    Assert-True $rejected 'Assertion accepted unencoded HTML evidence.'
}
Run-Case 'role-disagreement' { param($f); (Get-Evidence $f 'DC-02/Identity').Pdc = 'DC-02.techworks.local' } {
    param($r); Assert-True ($r.Summary.Health -eq 'FAIL') 'Cross-DC role disagreement passed.'
}
Run-Case 'invalid-evidence' { param($f); (Get-Evidence $f 'DC-02/Time').Remove('LastSync') } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Time').Error.Category -eq 'InvalidEvidence') 'Malformed evidence not caught.'
}
Run-Case 'machine-client-mismatch' { param($f); (Get-Evidence $f 'DC-02/MachineRead').Client = 'TW-CL01' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/MachineRead').Status -eq 'UNKNOWN') 'Machine identity/client mismatch passed.'
}
Run-Case 'machine-string-boolean' { param($f); (Get-Evidence $f 'DC-02/MachineRead').Reads[0].Readable = 'false' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/MachineRead').Status -eq 'UNKNOWN') 'String boolean passed.'
}
Run-Case 'dns-duplicated-query' { param($f); (Get-Evidence $f 'DC-02/DNS').Answers[7].Query = '_ldap._tcp.dc._msdcs.techworks.local' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/DNS').Status -eq 'UNKNOWN') 'Duplicated DNS query passed.'
}
Run-Case 'srv-wrong-address' { param($f); (Get-Evidence $f 'DC-02/DNS').Answers[3].Resolved[0].Addresses = @('192.168.1.99') } {
    param($r); Assert-True ((Find-Check $r 'DC-02/DNS').Status -eq 'FAIL') 'Wrong resolved SRV address passed.'
}
Run-Case 'wrong-offset-observer' { param($f); (Get-Evidence $f 'DC-02/Offset').Observer = 'ManagementPC' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Offset').Status -eq 'UNKNOWN') 'Management clock offset passed as DC offset.'
}
Run-Case 'wrong-event-channel' { param($f); (Get-Evidence $f 'DC-02/Events:System').Log = 'Application' } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Events:System').Status -eq 'UNKNOWN') 'Wrong channel passed.'
}
Run-Case 'disabled-event-channel' { param($f); (Get-Evidence $f 'DC-02/Events:System').Enabled = $false } {
    param($r); Assert-True ((Find-Check $r 'DC-02/Events:System').Status -eq 'UNKNOWN') 'Disabled channel passed.'
}
Run-Case 'optional-incomplete' { param($f); $f.Checks = @($f.Checks | Where-Object { $_.CheckId -ne 'TW-CL01/ClientDNS' }) } {
    param($r); Assert-True ($r.Summary.OptionalCompleteness -eq 'INCOMPLETE' -and $r.Summary.HealthyAndComplete) 'Optional coverage contaminated mandatory coverage.'
} @{ Clients = @('TW-CL01') }
Run-Case 'gp7017-information-event' {
    param($f); (Get-Evidence $f 'TW-CL01/Events:Microsoft-Windows-GroupPolicy/Operational').Events = @(@{
        Computer = 'TW-CL01'; Provider = 'Microsoft-Windows-GroupPolicy'; Id = 7017; Level = 4; Message = 'Synthetic error 5'; Xml = '<Event><Data>5</Data></Event>' })
} { param($r); Assert-True ((Find-Check $r 'TW-CL01/Events:Microsoft-Windows-GroupPolicy/Operational').Status -eq 'WARN') 'Information-level 7017 missed.' } @{ Clients = @('TW-CL01') }

$localRejected = $false
try { Invoke-SAM012Audit -FixturePath '\\never-contact\share\fixture.json' -OutputDirectory $OutputDirectory } catch { $localRejected = $_.Exception.Message -like '*local filesystem*' }
Assert-True $localRejected 'UNC fixture was not rejected before file access.'
$script:passed++; Write-Output 'PASS unc-fixture-rejected'
$scopeRejected = $false
try { Invoke-SAM012Audit -FixturePath (Join-Path $OutputDirectory 'healthy-and-reports.fixture.json') -OutputDirectory $OutputDirectory -Clients 'OTHER' } catch { $scopeRejected = $true }
Assert-True $scopeRejected 'Client outside allowlist accepted.'
$script:passed++; Write-Output 'PASS client-allowlist-rejected'

# Exhaust the collection budget using a local mock; no real collectors are used.
& $module { function script:Test-SAM012Evidence { param($Kind, $Evidence, $Target, $Options, $NowUtc)
    Start-Sleep -Milliseconds 1200
    [pscustomobject]@{ Status = 'PASS'; Complete = $true; Findings = @() }
} }
$budgetResult = Invoke-SAM012Audit -FixturePath (Join-Path $OutputDirectory 'healthy-and-reports.fixture.json') -OutputDirectory $OutputDirectory -OverallTimeoutSeconds 1
Assert-True ($budgetResult.Report.Summary.Completeness -eq 'INCOMPLETE' -and @($budgetResult.Report.Checks | Where-Object { $_.Error -and $_.Error.Message -eq 'Overall audit deadline exceeded.' }).Count -gt 0) 'Overall deadline did not mark skipped evidence.'
$script:passed++; Write-Output 'PASS overall-deadline'

# Restore module to exercise real local job deadline without Windows/network calls.
Import-Module $modulePath -Force
$bounded = Invoke-SAM012Bounded -ScriptBlock { Start-Sleep -Seconds 5 } -Arguments @() -TimeoutSeconds 1
Assert-True ($bounded.Error.Category -eq 'Timeout') 'Bounded local job did not timeout.'
$script:passed++; Write-Output 'PASS bounded-local-job-timeout'
$response = Invoke-SAM012Bounded -ScriptBlock { [pscustomobject]@{ Success = $true; Evidence = @{ Local = $true }; Error = $null } } -Arguments @() -TimeoutSeconds 10
Assert-True $response.Success 'Bounded local job result failed.'
$script:passed++; Write-Output 'PASS bounded-local-job-success'
$invalid = $false
try { Invoke-SAM012Audit -FixturePath (Join-Path $OutputDirectory 'healthy-and-reports.fixture.json') -OutputDirectory $OutputDirectory -OffsetWarnSeconds 5 -OffsetFailSeconds 1 } catch { $invalid = $true }
Assert-True $invalid 'Invalid threshold ordering accepted.'
$script:passed++; Write-Output 'PASS invalid-threshold-rejected'
Write-Output ("RESULT: $script:passed tests passed. Artifacts: $OutputDirectory")
