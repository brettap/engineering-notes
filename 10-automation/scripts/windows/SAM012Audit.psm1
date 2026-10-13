#requires -Version 5.1
Set-StrictMode -Version 2.0

# Fixed targets: no discovery-driven expansion, IP remoting, or wildcard hosts.
$script:Targets = @(
    [pscustomobject]@{ Name = 'Techworks-DC01'; Fqdn = 'Techworks-DC01.techworks.local'; IP = '192.168.1.51'; Peer = 'DC-02' },
    [pscustomobject]@{ Name = 'DC-02'; Fqdn = 'DC-02.techworks.local'; IP = '192.168.1.60'; Peer = 'Techworks-DC01' }
)
$script:Logs = @('System', 'Directory Service', 'DNS Server', 'DFS Replication', 'Microsoft-Windows-GroupPolicy/Operational')

function New-SAM012Options {
    param($Parameters)
    $o = @{
        EventLookbackHours = 24; MaxEventsPerLog = 200; CheckTimeoutSeconds = 30
        EventTimeoutSeconds = 60; OverallTimeoutSeconds = 600; ReplicationWarnMinutes = 60
        SyncWarnMinutes = 120; OffsetWarnSeconds = 1.0; OffsetFailSeconds = 5.0
        EvidenceMaxAgeHours = 24; ApprovedTimePeers = @('time.windows.com', 'time.nist.gov')
        ExpectedTimeZone = 'Eastern Standard Time'
    }
    foreach ($k in @($o.Keys)) { if ($Parameters.ContainsKey($k)) { $o[$k] = $Parameters[$k] } }
    if ($o.OffsetFailSeconds -le $o.OffsetWarnSeconds) { throw 'OffsetFailSeconds must exceed OffsetWarnSeconds.' }
    return $o
}

function Assert-SAM012LocalPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.StartsWith('\\') -or $Path.StartsWith('//') -or $Path -match '::|^[a-z]+://') {
        throw 'SAM-012 requires a local filesystem path.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $drive = New-Object IO.DriveInfo($root)
    if ($drive.DriveType -eq [IO.DriveType]::Network) { throw 'Mapped network paths are not permitted.' }
    return $full
}

# Every remote script verifies the actual hostname before collecting evidence.
# Invocation is performed in a bounded local job; no tasks/services are installed.
$script:RemoteCollector = {
    param($Name, $Kind, $Options, $ExpectedName)
    $ErrorActionPreference = 'Stop'
    if ($env:COMPUTERNAME -ine $ExpectedName) { throw 'SAM012.IdentityMismatch: unexpected remote computer.' }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    switch ($Kind) {
        'Identity' {
            Import-Module ActiveDirectory -ErrorAction Stop
            $dc = Get-ADDomainController -Identity $Name -Server $Name
            $domain = Get-ADDomain -Server $Name
            $forest = Get-ADForest -Server $Name
            [pscustomobject]@{ Hostname = $env:COMPUTERNAME; Domain = $domain.DNSRoot; Forest = $forest.Name
                ForestRoot = $forest.RootDomain; Site = $dc.Site; IsGC = $dc.IsGlobalCatalog
                Pdc = $domain.PDCEmulator; Address = $dc.IPv4Address; Identity = $identity }
        }
        'Replication' {
            Import-Module ActiveDirectory -ErrorAction Stop
            $root = Get-ADRootDSE -Server $Name
            $partners = @(Get-ADReplicationPartnerMetadata -Target $Name -Scope Server -Partition '*' -PartnerType Inbound -Server $Name |
                Select-Object Partition, Partner, LastReplicationSuccess, LastReplicationResult, ConsecutiveReplicationFailures)
            $failures = @(Get-ADReplicationFailure -Target $Name -Scope Server -Server $Name |
                Select-Object Partner, FailureCount, FirstFailureTime, LastError)
            [pscustomobject]@{ Partitions = @($root.namingContexts); Partners = $partners; Failures = $failures; Identity = $identity }
        }
        'Shares' {
            $shares = foreach ($shareName in @('SYSVOL', 'NETLOGON')) {
                $s = Get-SmbShare -Name $shareName
                $acl = Get-Acl -LiteralPath $s.Path
                $policy = $null
                if ($shareName -eq 'SYSVOL') {
                    $policyPath = Join-Path $s.Path 'techworks.local\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\gpt.ini'
                    $policyAcl = Get-Acl -LiteralPath $policyPath
                    $policy = [pscustomobject]@{ Path = $policyPath; Sddl = $policyAcl.Sddl
                        Content = @(Get-Content -LiteralPath $policyPath -TotalCount 20) }
                }
                [pscustomobject]@{ Name = $s.Name; Path = $s.Path; Sddl = $acl.Sddl
                    ShareAcl = @(Get-SmbShareAccess -Name $shareName | Select-Object AccountName, AccessControlType, AccessRight)
                    Policy = $policy }
            }
            [pscustomobject]@{ Shares = @($shares); Identity = $identity }
        }
        'Services' {
            $names = @('NTDS', 'DNS', 'Netlogon', 'Kdc', 'DFSR', 'LanmanServer', 'W32Time', 'WinRM', 'EventLog', 'TermService')
            [pscustomobject]@{ Services = @(Get-Service -Name $names | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Status = [string]$_.Status; StartType = [string]$_.StartType }
            }); Identity = $identity }
        }
        'Time' {
            # Native English labels parsed conservatively; unsupported localization
            # produces UNKNOWN. Raw text and every exit code are retained.
            $raw = @()
            foreach ($query in @('source', 'status', 'configuration', 'peers')) {
                $text = @(& w32tm.exe /query "/$query" /verbose 2>&1 | ForEach-Object { [string]$_ })
                $exit = $LASTEXITCODE
                $raw += [pscustomobject]@{ Query = $query; ExitCode = $exit; Output = $text }
            }
            $config = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
            $fields = @{}
            foreach ($line in ($raw | Where-Object { $_.Query -eq 'status' }).Output) {
                if ($line -match '^\s*(Source|Last Successful Sync Time|Leap Indicator|Stratum):\s*(.+)$') { $fields[$Matches[1]] = $Matches[2] }
            }
            $lastSync = $null; $leap = $null; $stratum = $null; $parsed = $true
            try {
                $lastSync = [datetime]::Parse($fields['Last Successful Sync Time'], [Globalization.CultureInfo]::CurrentCulture).ToUniversalTime().ToString('o')
                if ($fields['Leap Indicator'] -match '^(\d+)') { $leap = [int]$Matches[1] } else { $parsed = $false }
                if ($fields['Stratum'] -match '^(\d+)') { $stratum = [int]$Matches[1] } else { $parsed = $false }
            } catch { $parsed = $false }
            if (@($raw | Where-Object { $_.ExitCode -ne 0 }).Count -gt 0 -or -not $fields.ContainsKey('Source')) { $parsed = $false }
            [pscustomobject]@{ Source = $fields['Source']; LastSync = $lastSync
                LeapIndicator = $leap; Stratum = $stratum; Type = $config.Type; ParseSuccess = $parsed
                Culture = [Globalization.CultureInfo]::CurrentCulture.Name
                Peers = $config.NtpServer; TimeZone = (Get-TimeZone).Id; Raw = $raw; Identity = $identity }
        }
        'Offset' {
            # DC02 observer, DC01 destination: not management-host clock offset.
            $raw = @(& w32tm.exe /stripchart /computer:Techworks-DC01.techworks.local /samples:5 /period:1 /dataonly 2>&1 |
                ForEach-Object { [string]$_ })
            $exit = $LASTEXITCODE
            $samples = @()
            foreach ($line in $raw) {
                if ($line -match '([+-]\d+[\.,]\d+)s\s*$') {
                    $samples += [double]::Parse($Matches[1].Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            [pscustomobject]@{ Samples = $samples; ExitCode = $exit; Raw = $raw
                Observer = $env:COMPUTERNAME; Destination = 'Techworks-DC01.techworks.local'; Identity = $identity }
        }
        'ClientDNS' {
            [pscustomobject]@{ Interfaces = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 } |
                Select-Object InterfaceAlias, ServerAddresses); Identity = $identity }
        }
        default {
            if (-not $Kind.StartsWith('Events:')) { throw 'Unknown remote collection kind.' }
            $log = $Kind.Substring(7)
            $info = Get-WinEvent -ListLog $log
            if (-not $info.IsEnabled) { throw "SAM012.LogDisabled: $log" }
            $start = (Get-Date).ToUniversalTime().AddHours(-$Options.EventLookbackHours)
            $end = (Get-Date).ToUniversalTime()
            $filter = @{ LogName = $log; StartTime = $start; EndTime = $end }
            # Non-System channels include information-level evidence (e.g. GP 7017).
            if ($log -eq 'System') { $filter.Level = @(1, 2, 3) }
            try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents ($Options.MaxEventsPerLog + 1)) }
            catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $events = @() }
                else { throw }
            }
            $oldest = $null
            if ($info.RecordCount -gt 0) { $oldest = (Get-WinEvent -LogName $log -Oldest -MaxEvents 1).TimeCreated.ToUniversalTime().ToString('o') }
            [pscustomobject]@{ Log = $log; Enabled = $true; StartUtc = $start.ToString('o'); EndUtc = $end.ToString('o')
                OldestUtc = $oldest; Truncated = ($events.Count -gt $Options.MaxEventsPerLog)
                Events = @($events | Select-Object -First $Options.MaxEventsPerLog | ForEach-Object {
                    [pscustomobject]@{ Computer = $_.MachineName; Provider = $_.ProviderName; Id = $_.Id; Level = $_.Level
                        RecordId = $_.RecordId; TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('o')
                        Message = $_.Message; Xml = $_.ToXml() }
                }); Identity = $identity }
        }
    }
}

$script:Worker = {
    param($Target, $Kind, $Options, $Credential, $UserCredential, $RemoteText, $Metadata)
    $ErrorActionPreference = 'Stop'
    try {
        $remote = [scriptblock]::Create($RemoteText)
        $connection = @{ ComputerName = $Target.Fqdn; Authentication = 'Kerberos'; ErrorAction = 'Stop'
            SessionOption = (New-PSSessionOption -OpenTimeout ($Options.CheckTimeoutSeconds * 1000) -OperationTimeout ($Options.CheckTimeoutSeconds * 1000)) }
        if ($null -ne $Credential) { $connection.Credential = $Credential }
        if ($Kind -eq 'DNS') {
            $queries = @(
                @{ Query = 'Techworks-DC01.techworks.local'; Type = 'A'; Expected = @('192.168.1.51'); Port = 0 },
                @{ Query = 'DC-02.techworks.local'; Type = 'A'; Expected = @('192.168.1.60'); Port = 0 },
                @{ Query = 'techworks.local'; Type = 'A'; Expected = @('192.168.1.51', '192.168.1.60'); Port = 0 },
                @{ Query = '_ldap._tcp.dc._msdcs.techworks.local'; Type = 'SRV'; Expected = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 389 },
                @{ Query = '_kerberos._tcp.dc._msdcs.techworks.local'; Type = 'SRV'; Expected = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 88 },
                @{ Query = "_ldap._tcp.gc._msdcs.$($Metadata.Forest)"; Type = 'SRV'; Expected = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 3268 },
                @{ Query = '_ldap._tcp.pdc._msdcs.techworks.local'; Type = 'SRV'; Expected = @($Metadata.Pdc); Port = 389 },
                @{ Query = "_ldap._tcp.$($Metadata.Site)._sites.dc._msdcs.techworks.local"; Type = 'SRV'; Expected = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 389 }
            )
            $answers = foreach ($q in $queries) {
                try {
                    $records = @(Resolve-DnsName -Name $q.Query -Type $q.Type -Server $Target.IP -DnsOnly -NoHostsFile |
                        Where-Object { [string]$_.Type -eq $q.Type })
                    $values = @(); $ports = @(); $resolved = @()
                    foreach ($r in $records) {
                        if ($q.Type -eq 'A') { $values += $r.IPAddress }
                        else {
                            $hostName = $r.NameTarget.TrimEnd('.')
                            $values += $hostName; $ports += $r.Port
                            $a = @(Resolve-DnsName -Name $hostName -Type A -Server $Target.IP -DnsOnly -NoHostsFile |
                                Where-Object { [string]$_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
                            $resolved += [pscustomobject]@{ Target = $hostName; Addresses = $a }
                        }
                    }
                    [pscustomobject]@{ Query = $q.Query; Type = $q.Type; Expected = $q.Expected; ExpectedPort = $q.Port
                        Values = $values; Ports = $ports; Resolved = $resolved; Error = $null }
                } catch { [pscustomobject]@{ Query = $q.Query; Type = $q.Type; Expected = $q.Expected; ExpectedPort = $q.Port
                    Values = @(); Ports = @(); Resolved = @(); Error = $_.Exception.Message } }
            }
            $evidence = [pscustomobject]@{ Server = $Target.IP; Answers = @($answers); Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
        } elseif ($Kind -eq 'UserRead') {
            if ($null -eq $UserCredential) { throw 'SAM012.NotTested: supply a nonadministrative UserReadCredential.' }
            # A credential-specific PSDrive provides SMB authentication without tasks,
            # persistent mappings, or modifying the process identity.
            $reads = foreach ($root in @("\\$($Target.Fqdn)\SYSVOL", "\\$($Target.Fqdn)\NETLOGON", '\\techworks.local\SYSVOL')) {
                $drive = 'SAM' + [guid]::NewGuid().ToString('N').Substring(0, 8)
                try {
                    $null = New-PSDrive -Name $drive -PSProvider FileSystem -Root $root -Credential $UserCredential -Scope Local
                    $null = Get-Item -LiteralPath ($drive + ':\') -ErrorAction Stop
                    if ($root -like '*\SYSVOL') {
                        $null = Get-Content -LiteralPath ($drive + ':\techworks.local\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\gpt.ini') -TotalCount 20
                    }
                    [pscustomobject]@{ Path = $root; Readable = $true; Error = $null }
                } catch { [pscustomobject]@{ Path = $root; Readable = $false; Error = $_.Exception.Message } }
                finally { Remove-PSDrive -Name $drive -ErrorAction SilentlyContinue }
            }
            $evidence = [pscustomobject]@{ Context = 'SuppliedUser'; Identity = $UserCredential.UserName; Reads = @($reads) }
        } else {
            $evidence = Invoke-Command @connection -ScriptBlock $remote -ArgumentList $Target.Fqdn, $Kind, $Options, $Target.Name
        }
        [pscustomobject]@{ Success = $true; Evidence = $evidence; Error = $null }
    } catch {
        $category = [string]$_.CategoryInfo.Category
        if ($_.Exception.Message -like 'SAM012.NotTested:*') { $category = 'NotTested' }
        if ($_.Exception.Message -like '*SAM012.IdentityMismatch:*') { $category = 'IdentityMismatch' }
        [pscustomobject]@{ Success = $false; Evidence = $null
            Error = [pscustomobject]@{ Category = $category; Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId } }
    }
}

function Invoke-SAM012Bounded {
    param([scriptblock]$ScriptBlock, [object[]]$Arguments, [int]$TimeoutSeconds)
    $job = $null
    try {
        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $Arguments
        $done = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($null -eq $done) {
            return [pscustomobject]@{ Success = $false; Evidence = $null; Error = [pscustomobject]@{ Category = 'Timeout'; Message = 'Collection deadline exceeded.'; Id = 'SAM012.Timeout' } }
        }
        $result = @(Receive-Job -Job $job -ErrorAction Stop)
        if ($result.Count -ne 1 -or $null -eq $result[0].PSObject.Properties['Success']) { throw 'Invalid collector response.' }
        return $result[0]
    } catch {
        return [pscustomobject]@{ Success = $false; Evidence = $null; Error = [pscustomobject]@{ Category = 'CollectorError'; Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId } }
    } finally {
        if ($null -ne $job) { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-SAM012ShareAccessType {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $valueProperty = @($Value.Keys | Where-Object { [string]$_ -ceq 'Value' } | Select-Object -First 1)
        if ($valueProperty.Count -gt 0 -and $Value[$valueProperty[0]] -is [string]) { return $Value[$valueProperty[0]] }
    }
    $valueProperty = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq 'Value' -and $_.Value -is [string] } | Select-Object -First 1)
    if ($valueProperty.Count -gt 0) { return $valueProperty[0].Value }
    if ($Value -is [System.Enum]) { return $Value.ToString() }
    return [string]$Value
}

function Test-SAM012Evidence {
    param([string]$Kind, $Evidence, $Target, $Options, [datetime]$NowUtc)
    $fail = @(); $warn = @(); $unknown = @()
    switch ($Kind) {
        'Identity' {
            if ($Evidence.Hostname -ine $Target.Name -or $Evidence.Domain -ine 'techworks.local' -or $Evidence.Address -ne $Target.IP) { $fail += 'Target identity/domain/address differs from baseline.' }
            if (-not $Evidence.IsGC) { $fail += 'Documented global catalog role missing.' }
            if ($Evidence.Pdc -notin @('Techworks-DC01.techworks.local', 'DC-02.techworks.local')) { $fail += 'Discovered PDC is outside the approved two-DC scope.' }
            if ([string]::IsNullOrWhiteSpace($Evidence.Site) -or [string]::IsNullOrWhiteSpace($Evidence.Forest) -or [string]::IsNullOrWhiteSpace($Evidence.Pdc)) { $unknown += 'AD discovery incomplete.' }
        }
        'DNS' {
            if (@($Evidence.Answers).Count -ne 8 -or @($Evidence.Answers | Select-Object -ExpandProperty Query -Unique).Count -ne 8) { $unknown += 'DNS query coverage incomplete or duplicated.' }
            foreach ($answer in $Evidence.Answers) {
                if ($null -ne $answer.Error) { $unknown += "$($answer.Query): $($answer.Error)"; continue }
                foreach ($expected in $answer.Expected) { if ($answer.Values -inotcontains $expected) { $fail += "$($answer.Query): missing $expected" } }
                foreach ($value in $answer.Values) { if ($answer.Expected -inotcontains $value) { $warn += "$($answer.Query): unexpected answer $value" } }
                if ($answer.Type -eq 'SRV') {
                    if (@($answer.Ports).Count -ne @($answer.Values).Count -or @($answer.Resolved).Count -ne @($answer.Values).Count) { $unknown += 'SRV target coverage incomplete.' }
                    foreach ($port in $answer.Ports) { if ($port -ne $answer.ExpectedPort) { $fail += "$($answer.Query): wrong SRV port $port" } }
                    foreach ($r in $answer.Resolved) {
                        if (@($r.Addresses).Count -eq 0) { $fail += "SRV target $($r.Target) does not resolve." }
                        $expectedAddress = $null
                        if ($r.Target -ieq 'Techworks-DC01.techworks.local') { $expectedAddress = '192.168.1.51' }
                        if ($r.Target -ieq 'DC-02.techworks.local') { $expectedAddress = '192.168.1.60' }
                        if ($expectedAddress -and $r.Addresses -notcontains $expectedAddress) { $fail += "SRV target $($r.Target) does not resolve to its documented address." }
                    }
                }
            }
        }
        'Replication' {
            if (@($Evidence.Partitions).Count -eq 0) { $unknown += 'No hosted partitions returned.' }
            foreach ($partition in $Evidence.Partitions) {
                $partners = @($Evidence.Partners | Where-Object { $_.Partition -ieq $partition })
                if ($partners.Count -eq 0) { $unknown += "Missing inbound evidence for $partition"; continue }
                if (@($partners | Where-Object { $_.Partner -match (',CN=' + [regex]::Escape($Target.Peer) + ',') }).Count -eq 0) { $fail += "Expected partner absent for $partition" }
                foreach ($p in $partners) {
                    if ($p.LastReplicationResult -ne 0 -or $p.ConsecutiveReplicationFailures -gt 0) { $fail += "Replication failure: $partition / $($p.Partner)" }
                    if ($null -eq $p.LastReplicationSuccess) { $unknown += 'Missing replication timestamp.' }
                    else {
                        $age = ($NowUtc - ([datetime]$p.LastReplicationSuccess).ToUniversalTime()).TotalMinutes
                        if ($age -lt -1) { $unknown += 'Future replication timestamp.' }
                        elseif ($age -gt $Options.ReplicationWarnMinutes) { $warn += "Stale replication: $partition" }
                    }
                }
            }
            if (@($Evidence.Failures).Count -gt 0) { $fail += 'Replication failure cache contains entries.' }
        }
        'Shares' {
            foreach ($name in @('SYSVOL', 'NETLOGON')) {
                $s = @($Evidence.Shares | Where-Object { $_.Name -eq $name })
                if ($s.Count -ne 1) { $fail += "$name not published exactly once."; continue }
                if ([string]::IsNullOrWhiteSpace($s[0].Sddl)) { $unknown += "$name NTFS ACL missing." }
                $allow = @($s[0].ShareAcl | Where-Object {
                    (ConvertTo-SAM012ShareAccessType $_.AccessControlType) -eq 'Allow' -and $_.AccountName -in @('Everyone', 'NT AUTHORITY\Authenticated Users', 'TECHWORKS\Domain Computers')
                })
                if ($allow.Count -eq 0) { $fail += "$name lacks a recognized ordinary-client share grant (review localized principals)." }
                if (@($s[0].ShareAcl | Where-Object { (ConvertTo-SAM012ShareAccessType $_.AccessControlType) -eq 'Deny' }).Count -gt 0) { $warn += "$name has deny ACEs; effective access requires review." }
                if ($name -eq 'SYSVOL' -and ($null -eq $s[0].Policy -or [string]::IsNullOrWhiteSpace($s[0].Policy.Sddl))) { $unknown += 'Policy-file ACL evidence absent.' }
            }
        }
        'Services' {
            foreach ($name in @('NTDS', 'DNS', 'Netlogon', 'Kdc', 'DFSR', 'LanmanServer', 'W32Time', 'EventLog')) {
                $s = @($Evidence.Services | Where-Object { $_.Name -ieq $name })
                if ($s.Count -ne 1) { $unknown += "Missing service $name"; continue }
                if ($s[0].Status -ne 'Running') { $fail += "$name is $($s[0].Status)" }
                if ($s[0].StartType -eq 'Disabled') { $fail += "$name disabled." }
            }
            foreach ($s in $Evidence.Services) { if ($s.Name -in @('WinRM', 'TermService') -and $s.Status -ne 'Running') { $warn += "Management service $($s.Name) is $($s.Status)" } }
        }
        'Time' {
            if (-not $Evidence.ParseSuccess) {
                return [pscustomobject]@{ Status = 'UNKNOWN'; Complete = $false; Findings = @('Native time output was not fully parsed or a query failed; raw evidence retained.') }
            }
            if ($Evidence.Source -match 'Free-running|Local CMOS|LOCL' -or [string]::IsNullOrWhiteSpace($Evidence.Source)) { $fail += 'No usable selected time source.' }
            if ($Evidence.LeapIndicator -eq 3 -or $Evidence.Stratum -lt 1 -or $Evidence.Stratum -gt 15) { $fail += 'Time service reports unsynchronized/invalid state.' }
            if ($null -eq $Evidence.LastSync) { $unknown += 'Last successful synchronization unavailable.' }
            else {
                $age = ($NowUtc - ([datetime]$Evidence.LastSync).ToUniversalTime()).TotalMinutes
                if ($age -lt -1) { $unknown += 'Future synchronization timestamp.' }
                elseif ($age -gt $Options.SyncWarnMinutes) { $warn += 'Time synchronization is stale.' }
            }
            if ($Evidence.TimeZone -ne $Options.ExpectedTimeZone) { $warn += 'Time-zone baseline differs (separate from synchronization).' }
            if ($Evidence.IsForestRootPdc) {
                $source = ([string]$Evidence.Source -split ',')[0].TrimEnd('.')
                if ($Options.ApprovedTimePeers -inotcontains $source) { $fail += 'Forest-root PDC source is outside approved peers.' }
                if ($Evidence.Type -notin @('NTP', 'AllSync')) { $fail += 'Forest-root PDC lacks external-source time configuration.' }
            } elseif ($Evidence.Type -ne 'NT5DS') { $warn += 'Non-root-PDC differs from domain-hierarchy baseline.' }
        }
        'Offset' {
            if ($Evidence.Observer -ine 'DC-02' -or $Evidence.Destination -ine 'Techworks-DC01.techworks.local') { $unknown += 'Offset observer/destination does not match the DC-to-DC test.' }
            if ($Evidence.ExitCode -ne 0 -or @($Evidence.Samples).Count -ne 5) { $unknown += 'Five successful offset samples unavailable; raw output retained.' }
            else {
                $max = ($Evidence.Samples | ForEach-Object { [math]::Abs([double]$_) } | Measure-Object -Maximum).Maximum
                if ($max -ge $Options.OffsetFailSeconds) { $fail += 'DC-to-DC offset exceeds failure threshold.' }
                elseif ($max -gt $Options.OffsetWarnSeconds) { $warn += 'DC-to-DC offset exceeds warning threshold.' }
            }
        }
        'UserRead' {
            if ($Evidence.Context -ne 'SuppliedUser' -or [string]::IsNullOrWhiteSpace($Evidence.Identity)) { $unknown += 'User identity evidence missing.' }
            if (@($Evidence.Reads).Count -ne 3) { $unknown += 'User SMB evidence incomplete.' }
            foreach ($r in $Evidence.Reads) { if (-not $r.Readable) { $fail += "SMB read failed: $($r.Path): $($r.Error)" } }
            # Credentials are operator-attested nonadministrative; token not inferred.
        }
        'MachineRead' {
            if ($Evidence.Context -ne 'Machine' -or $Evidence.Identity -notmatch '^TECHWORKS\\TW-CL0[012]\$$' -or $Evidence.Client -notin @('TW-CL00', 'TW-CL01', 'TW-CL02')) { $unknown += 'Machine-context evidence identity invalid.' }
            if ($Evidence.Target -ine $Target.Fqdn) { $unknown += 'Machine evidence target mismatch.' }
            if ($Evidence.Identity -ine ('TECHWORKS\' + $Evidence.Client + '$')) { $unknown += 'Machine identity does not match the stated client.' }
            $age = ($NowUtc - ([datetime]$Evidence.TimestampUtc).ToUniversalTime()).TotalHours
            if ($age -lt 0 -or $age -gt $Options.EvidenceMaxAgeHours) { $unknown += 'Machine evidence is stale or from the future.' }
            foreach ($required in @('SYSVOL', 'NETLOGON', 'PolicyFile')) {
                $r = @($Evidence.Reads | Where-Object { $_.Resource -eq $required })
                if ($r.Count -ne 1) { $unknown += "Machine evidence missing $required" }
                elseif ($r[0].Readable -isnot [bool]) { $unknown += "Machine read $required must contain a JSON boolean." }
                elseif (-not $r[0].Readable) { $fail += "Machine cannot read $required" }
            }
        }
        'ClientDNS' {
            if (@($Evidence.Interfaces).Count -eq 0) { $unknown += 'No configured client DNS interfaces returned.' }
            foreach ($interface in $Evidence.Interfaces) {
                if ($interface.ServerAddresses -notcontains '192.168.1.51' -or $interface.ServerAddresses -notcontains '192.168.1.60') { $warn += "$($interface.InterfaceAlias): both AD resolvers not configured." }
            }
        }
        default {
            if (-not $Kind.StartsWith('Events:')) { throw "Unknown evaluator $Kind" }
            if ($Evidence.Log -ne $Kind.Substring(7)) { $unknown += 'Evidence log does not match the requested channel.' }
            if (-not $Evidence.Enabled) { $unknown += 'Event channel disabled.' }
            if ($Evidence.Truncated) { $unknown += 'Event collection truncated.' }
            if ($null -eq $Evidence.OldestUtc -or ([datetime]$Evidence.OldestUtc).ToUniversalTime() -gt ([datetime]$Evidence.StartUtc).ToUniversalTime()) { $unknown += 'Retained event history does not cover requested window.' }
            foreach ($event in $Evidence.Events) {
                if (($event.Computer -split '\.')[0] -ine $Target.Name) { $unknown += 'Event evidence belongs to another host.' }
                if ($event.Level -in @(1, 2, 3)) { $warn += "$($event.Provider)/$($event.Id): historical warning/error; assess current checks independently." }
                if ($event.Provider -eq 'Microsoft-Windows-GroupPolicy' -and $event.Id -eq 7017) { $warn += 'GroupPolicy/7017 evidence: inspect XML error code and execution context.' }
            }
        }
    }
    $status = 'PASS'
    if ($warn.Count -gt 0) { $status = 'WARN' }
    if ($unknown.Count -gt 0) { $status = 'UNKNOWN' }
    if ($fail.Count -gt 0) { $status = 'FAIL' }
    [pscustomobject]@{ Status = $status; Complete = ($unknown.Count -eq 0); Findings = @($fail + $warn + $unknown) }
}

function Write-SAM012Reports {
    param($Report, [string]$OutputDirectory)
    $directory = Assert-SAM012LocalPath $OutputDirectory
    $null = [IO.Directory]::CreateDirectory($directory)
    $base = Join-Path $directory ('SAM-012-' + $Report.RunId)
    $paths = [pscustomobject]@{ Json = ($base + '.json'); Html = ($base + '.html'); Csv = ($base + '.csv') }
    foreach ($p in @($paths.Json, $paths.Html, $paths.Csv)) { if ([IO.File]::Exists($p)) { throw 'Report already exists; refusing overwrite.' } }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($paths.Json, ($Report | ConvertTo-Json -Depth 30), $utf8)
    $flat = @($Report.Checks | Select-Object CheckId, Target, Scope, Mandatory, Status, Complete, Transport, Identity, StartedUtc, EndedUtc,
        @{ Name = 'Findings'; Expression = { $_.Findings -join ' | ' } },
        @{ Name = 'Error'; Expression = { if ($null -ne $_.Error) { $_.Error | ConvertTo-Json -Compress } } })
    [IO.File]::WriteAllLines($paths.Csv, [string[]]@($flat | ConvertTo-Csv -NoTypeInformation), $utf8)
    $rows = foreach ($c in $Report.Checks) {
        '<tr><td>' + [Net.WebUtility]::HtmlEncode($c.Target) + '</td><td>' + [Net.WebUtility]::HtmlEncode($c.CheckId) +
        '</td><td>' + $c.Scope + '</td><td>' + $c.Status + '</td><td>' + $c.Complete + '</td><td>' +
        [Net.WebUtility]::HtmlEncode(($c.Findings -join '; ')) + '</td></tr>'
    }
    $evidence = [Net.WebUtility]::HtmlEncode(($Report | ConvertTo-Json -Depth 30))
    $html = '<!doctype html><html lang="en"><meta charset="utf-8"><title>SAM-012 AD audit</title>' +
        '<style>body{font:16px sans-serif;margin:2rem}table{border-collapse:collapse}td,th{border:1px solid #aaa;padding:.4rem}pre{white-space:pre-wrap}</style>' +
        '<h1>SAM-012 AD Health Audit</h1><p>Mode: ' + $Report.Mode + '; mandatory health: ' + $Report.Summary.Health +
        '; mandatory evidence: ' + $Report.Summary.Completeness + '; optional evidence: ' + $Report.Summary.OptionalCompleteness +
        '</p><p>Fixture reports are synthetic. PASS applies only to the named check; no failover or interactive RDP claim.</p>' +
        '<table><tr><th>Target</th><th>Check</th><th>Scope</th><th>Status</th><th>Complete</th><th>Findings</th></tr>' + ($rows -join '') +
        '</table><details><summary>Full evidence and errors</summary><pre>' + $evidence + '</pre></details></html>'
    [IO.File]::WriteAllText($paths.Html, $html, $utf8)
    return $paths
}

function Invoke-SAM012Audit {
    [CmdletBinding(DefaultParameterSetName = 'Fixture')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Live')][switch]$Live,
        [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')][string]$FixturePath,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [string[]]$Clients = @(), [pscredential]$Credential, [pscredential]$UserReadCredential, [string]$MachineEvidencePath,
        [ValidateRange(1, 168)][int]$EventLookbackHours = 24, [ValidateRange(1, 10000)][int]$MaxEventsPerLog = 200,
        [ValidateRange(1, 3600)][int]$CheckTimeoutSeconds = 30, [ValidateRange(1, 3600)][int]$EventTimeoutSeconds = 60,
        [ValidateRange(1, 86400)][int]$OverallTimeoutSeconds = 600, [ValidateRange(1, 10080)][int]$ReplicationWarnMinutes = 60,
        [ValidateRange(1, 10080)][int]$SyncWarnMinutes = 120, [ValidateRange(0.001, 300)][double]$OffsetWarnSeconds = 1,
        [ValidateRange(0.001, 300)][double]$OffsetFailSeconds = 5, [ValidateRange(1, 168)][int]$EvidenceMaxAgeHours = 24,
        [string[]]$ApprovedTimePeers = @('time.windows.com', 'time.nist.gov'), [string]$ExpectedTimeZone = 'Eastern Standard Time'
    )
    $options = New-SAM012Options $PSBoundParameters
    $OutputDirectory = Assert-SAM012LocalPath $OutputDirectory
    foreach ($client in $Clients) { if ($client -notin @('TW-CL00', 'TW-CL01', 'TW-CL02')) { throw "Client outside allowlist: $client" } }
    $fixture = $null; $machine = @()
    if ($PSCmdlet.ParameterSetName -eq 'Fixture') {
        $FixturePath = Assert-SAM012LocalPath $FixturePath
        $fixture = Get-Content -LiteralPath $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($fixture.SchemaVersion -ne 1) { throw 'Unsupported fixture schema.' }
    } else {
        if (-not $Live) { throw 'Live collection requires -Live.' }
        if ($PSVersionTable.PSEdition -eq 'Core' -or $env:OS -ne 'Windows_NT') { throw 'Live mode requires Windows PowerShell 5.1 on Windows.' }
        foreach ($module in @('ActiveDirectory', 'DnsClient')) { if (-not (Get-Module -ListAvailable -Name $module)) { throw "Missing prerequisite module: $module" } }
        if ($MachineEvidencePath) {
            $MachineEvidencePath = Assert-SAM012LocalPath $MachineEvidencePath
            $machine = @(Get-Content -LiteralPath $MachineEvidencePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
        }
    }
    $start = [datetime]::UtcNow; $timer = [Diagnostics.Stopwatch]::StartNew()
    $now = $start
    if ($null -ne $fixture) { $now = ([datetime]$fixture.NowUtc).ToUniversalTime() }
    $plan = @()
    foreach ($target in $script:Targets) {
        foreach ($kind in @('Identity', 'DNS', 'Replication', 'Shares', 'Services', 'Time', 'UserRead', 'MachineRead')) {
            $plan += [pscustomobject]@{ Target = $target; Kind = $kind; Mandatory = $true; Scope = 'DC' }
        }
        if ($target.Name -eq 'DC-02') { $plan += [pscustomobject]@{ Target = $target; Kind = 'Offset'; Mandatory = $true; Scope = 'DC' } }
        foreach ($log in $script:Logs) { $plan += [pscustomobject]@{ Target = $target; Kind = ('Events:' + $log); Mandatory = $true; Scope = 'DC' } }
    }
    foreach ($client in ($Clients | Select-Object -Unique)) {
        $target = [pscustomobject]@{ Name = $client; Fqdn = ($client + '.techworks.local'); IP = $null; Peer = $null }
        foreach ($kind in @('ClientDNS', 'Events:Microsoft-Windows-GroupPolicy/Operational')) {
            $plan += [pscustomobject]@{ Target = $target; Kind = $kind; Mandatory = $false; Scope = 'Client' }
        }
    }
    $checks = @(); $metadata = @{}; $identityOK = @{}
    foreach ($item in $plan) {
        $target = $item.Target; $kind = $item.Kind; $id = $target.Name + '/' + $kind
        $checkStart = [datetime]::UtcNow; $result = $null; $skip = $null
        if ($timer.Elapsed.TotalSeconds -ge $options.OverallTimeoutSeconds) { $skip = 'Overall audit deadline exceeded.' }
        elseif ($item.Scope -eq 'DC' -and $kind -ne 'Identity' -and -not $identityOK[$target.Name]) { $skip = 'Target identity was not verified; dependent check skipped.' }
        if ($skip) {
            $result = [pscustomobject]@{ Success = $false; Evidence = $null; Error = [pscustomobject]@{ Category = 'Dependency'; Message = $skip; Id = 'SAM012.Skipped' } }
        } elseif ($null -ne $fixture) {
            $match = @($fixture.Checks | Where-Object { $_.CheckId -eq $id })
            if ($match.Count -eq 1) { $result = $match[0].Result }
            else { $result = [pscustomobject]@{ Success = $false; Evidence = $null; Error = [pscustomobject]@{ Category = 'FixtureMissing'; Message = 'Fixture check missing or duplicated.'; Id = 'SAM012.FixtureMissing' } } }
        } elseif ($kind -eq 'MachineRead') {
            $match = @($machine | Where-Object { $_.Target -ieq $target.Fqdn })
            if ($match.Count -eq 1) { $result = [pscustomobject]@{ Success = $true; Evidence = $match[0]; Error = $null } }
            else { $result = [pscustomobject]@{ Success = $false; Evidence = $null; Error = [pscustomobject]@{ Category = 'NotTested'; Message = 'One fresh external machine-context record per DC is required.'; Id = 'SAM012.MachineContext' } } }
        } else {
            $timeout = $options.CheckTimeoutSeconds
            if ($kind.StartsWith('Events:')) { $timeout = $options.EventTimeoutSeconds }
            $timeout = [math]::Min($timeout, [math]::Max(1, [math]::Floor($options.OverallTimeoutSeconds - $timer.Elapsed.TotalSeconds)))
            $result = Invoke-SAM012Bounded -ScriptBlock $script:Worker -TimeoutSeconds $timeout -Arguments @(
                $target, $kind, $options, $Credential, $UserReadCredential, $script:RemoteCollector.ToString(), $metadata[$target.Name])
        }
        $evaluation = [pscustomobject]@{ Status = 'UNKNOWN'; Complete = $false; Findings = @() }
        $errorRecord = $result.Error
        if ($result.Success) {
            try {
                if ($kind -eq 'Time') {
                    $m = $metadata[$target.Name]
                    $isRootPdc = ($m.Domain -ieq $m.ForestRoot -and $m.Pdc -ieq $target.Fqdn)
                    $result.Evidence | Add-Member -NotePropertyName IsForestRootPdc -NotePropertyValue $isRootPdc -Force
                }
                $evaluation = Test-SAM012Evidence -Kind $kind -Evidence $result.Evidence -Target $target -Options $options -NowUtc $now
                if ($kind -eq 'Identity' -and $evaluation.Status -eq 'PASS') { $metadata[$target.Name] = $result.Evidence; $identityOK[$target.Name] = $true }
            } catch {
                $errorRecord = [pscustomobject]@{ Category = 'InvalidEvidence'; Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId }
                $evaluation = [pscustomobject]@{ Status = 'UNKNOWN'; Complete = $false; Findings = @('Evidence could not be evaluated.') }
            }
        } else {
            $evaluation.Findings = @($errorRecord.Message)
            if ($errorRecord.Category -eq 'NotTested') { $evaluation.Status = 'NOT TESTED' }
            if ($errorRecord.Category -eq 'IdentityMismatch') { $evaluation.Status = 'FAIL' }
        }
        $identity = $null
        if ($null -ne $result.Evidence -and $null -ne $result.Evidence.PSObject.Properties['Identity']) { $identity = $result.Evidence.Identity }
        $transport = 'WinRM/Kerberos'
        if ($null -ne $fixture) { $transport = 'Fixture (no network)' }
        elseif ($kind -eq 'DNS') { $transport = 'DNS/direct server' }
        elseif ($kind -eq 'UserRead') { $transport = 'SMB/temporary PSDrive' }
        elseif ($kind -eq 'MachineRead') { $transport = 'Imported evidence' }
        $observer = $target.Name
        if ($kind -in @('DNS', 'UserRead')) { $observer = [Environment]::MachineName }
        if ($kind -eq 'MachineRead' -and $null -ne $result.Evidence -and $null -ne $result.Evidence.PSObject.Properties['Client']) { $observer = $result.Evidence.Client }
        $checks += [pscustomobject]@{ CheckId = $id; Target = $target.Fqdn; Scope = $item.Scope; Mandatory = $item.Mandatory
            Status = $evaluation.Status; Complete = $evaluation.Complete; Findings = $evaluation.Findings
            Observer = $observer; Identity = $identity; Transport = $transport
            StartedUtc = $checkStart.ToString('o'); EndedUtc = [datetime]::UtcNow.ToString('o')
            Evidence = $result.Evidence; Error = $errorRecord }
    }
    # Cross-DC role discovery consistency is part of mandatory identity coverage.
    if ($metadata.Count -eq 2) {
        $a = $metadata['Techworks-DC01']; $b = $metadata['DC-02']
        if ($a.Pdc -ine $b.Pdc -or $a.Forest -ine $b.Forest -or $a.ForestRoot -ine $b.ForestRoot) {
            foreach ($c in $checks | Where-Object { $_.CheckId -like '*/Identity' }) { $c.Status = 'FAIL'; $c.Findings += 'Cross-DC forest/PDC discovery disagrees.' }
        }
    }
    $mandatory = @($checks | Where-Object { $_.Mandatory }); $optional = @($checks | Where-Object { -not $_.Mandatory })
    $health = 'PASS'
    if (@($mandatory | Where-Object { $_.Status -eq 'WARN' }).Count) { $health = 'WARN' }
    if (@($mandatory | Where-Object { $_.Status -in @('UNKNOWN', 'NOT TESTED') }).Count) { $health = 'UNKNOWN' }
    if (@($mandatory | Where-Object { $_.Status -eq 'FAIL' }).Count) { $health = 'FAIL' }
    $complete = (@($mandatory | Where-Object { -not $_.Complete }).Count -eq 0)
    $optionalComplete = 'NOT REQUESTED'
    if ($optional.Count -gt 0) {
        $optionalComplete = 'COMPLETE'
        if (@($optional | Where-Object { -not $_.Complete }).Count) { $optionalComplete = 'INCOMPLETE' }
    }
    $mode = 'Live'; if ($null -ne $fixture) { $mode = 'Fixture' }
    $report = [pscustomobject]@{ SchemaVersion = 1; Audit = 'SAM-012'; RunId = [guid]::NewGuid().ToString('N'); Mode = $mode
        StartedUtc = $start.ToString('o'); EndedUtc = [datetime]::UtcNow.ToString('o'); EvaluationUtc = $now.ToString('o')
        Options = $options; Summary = [pscustomobject]@{ Health = $health; Completeness = $(if ($complete) { 'COMPLETE' } else { 'INCOMPLETE' })
            HealthyAndComplete = ($complete -and $health -eq 'PASS'); MandatoryChecks = $mandatory.Count
            OptionalChecks = $optional.Count; OptionalCompleteness = $optionalComplete }
        Limitations = @('No failover or interactive RDP test.', 'AD replication does not prove full SYSVOL convergence.',
            'Ordinary user credentials must be operator-attested nonadministrative.', 'Imported machine evidence is operator-supplied, not cryptographically attested.')
        Checks = $checks }
    $paths = Write-SAM012Reports -Report $report -OutputDirectory $OutputDirectory
    [pscustomobject]@{ Report = $report; Paths = $paths }
}

Export-ModuleMember -Function Invoke-SAM012Audit, Test-SAM012Evidence, Invoke-SAM012Bounded
