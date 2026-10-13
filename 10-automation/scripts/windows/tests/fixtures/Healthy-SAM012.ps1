# Pure synthetic fixture builder: no Windows cmdlets, remoting, or DNS calls.
function New-SAM012HealthyFixture {
    $now = [datetime]'2026-10-13T16:00:00Z'
    $checks = @()
    $targets = @(
        @{ Name = 'Techworks-DC01'; IP = '192.168.1.51'; Peer = 'DC-02' },
        @{ Name = 'DC-02'; IP = '192.168.1.60'; Peer = 'Techworks-DC01' }
    )
    foreach ($t in $targets) {
        $fqdn = $t.Name + '.techworks.local'
        $data = @{}
        $data.Identity = @{ Hostname = $t.Name; Domain = 'techworks.local'; Address = $t.IP; IsGC = $true
            Forest = 'techworks.local'; ForestRoot = 'techworks.local'; Site = 'Default-First-Site-Name'
            Pdc = 'Techworks-DC01.techworks.local'; Identity = 'TECHWORKS\audit' }
        $answers = @()
        foreach ($q in @(
            @{ Name = 'Techworks-DC01.techworks.local'; Values = @('192.168.1.51'); Port = 0 },
            @{ Name = 'DC-02.techworks.local'; Values = @('192.168.1.60'); Port = 0 },
            @{ Name = 'techworks.local'; Values = @('192.168.1.51', '192.168.1.60'); Port = 0 },
            @{ Name = '_ldap._tcp.dc._msdcs.techworks.local'; Values = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 389 },
            @{ Name = '_kerberos._tcp.dc._msdcs.techworks.local'; Values = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 88 },
            @{ Name = '_ldap._tcp.gc._msdcs.techworks.local'; Values = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 3268 },
            @{ Name = '_ldap._tcp.pdc._msdcs.techworks.local'; Values = @('Techworks-DC01.techworks.local'); Port = 389 },
            @{ Name = '_ldap._tcp.Default-First-Site-Name._sites.dc._msdcs.techworks.local'; Values = @('Techworks-DC01.techworks.local', 'DC-02.techworks.local'); Port = 389 }
        )) {
            $type = 'A'; $ports = @(); $resolved = @()
            if ($q.Port -gt 0) {
                $type = 'SRV'
                foreach ($value in $q.Values) {
                    $ports += $q.Port
                    $ip = '192.168.1.51'; if ($value -like 'DC-02.*') { $ip = '192.168.1.60' }
                    $resolved += @{ Target = $value; Addresses = @($ip) }
                }
            }
            $answers += @{ Query = $q.Name; Type = $type; Expected = $q.Values; Values = $q.Values
                ExpectedPort = $q.Port; Ports = $ports; Resolved = $resolved; Error = $null }
        }
        $data.DNS = @{ Server = $t.IP; Answers = $answers; Identity = 'TECHWORKS\audit' }
        $partitions = @('DC=techworks,DC=local', 'CN=Configuration,DC=techworks,DC=local', 'CN=Schema,CN=Configuration,DC=techworks,DC=local',
            'DC=DomainDnsZones,DC=techworks,DC=local', 'DC=ForestDnsZones,DC=techworks,DC=local')
        $partners = foreach ($partition in $partitions) {
            @{ Partition = $partition; Partner = ('CN=NTDS Settings,CN=' + $t.Peer + ',CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=techworks,DC=local')
                LastReplicationSuccess = $now.AddMinutes(-5).ToString('o'); LastReplicationResult = 0; ConsecutiveReplicationFailures = 0 }
        }
        $data.Replication = @{ Partitions = $partitions; Partners = @($partners); Failures = @(); Identity = 'TECHWORKS\audit' }
        $shares = foreach ($share in @('SYSVOL', 'NETLOGON')) {
            @{ Name = $share; Path = ('C:\Windows\SYSVOL\' + $share); Sddl = 'O:SYG:SYD:(A;;FR;;;AU)'
                ShareAcl = @(@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Read' })
                Policy = @{ Path = 'fixture\gpt.ini'; Sddl = 'O:SYG:SYD:(A;;FR;;;AU)'; Content = @('[General]', 'Version=1') } }
        }
        $data.Shares = @{ Shares = @($shares); Identity = 'TECHWORKS\audit' }
        $services = foreach ($name in @('NTDS', 'DNS', 'Netlogon', 'Kdc', 'DFSR', 'LanmanServer', 'W32Time', 'EventLog', 'WinRM', 'TermService')) {
            @{ Name = $name; Status = 'Running'; StartType = 'Automatic' }
        }
        $data.Services = @{ Services = @($services); Identity = 'TECHWORKS\audit' }
        $source = 'time.windows.com,0x8'; $type = 'NTP'
        if ($t.Name -eq 'DC-02') { $source = 'Techworks-DC01.techworks.local'; $type = 'NT5DS' }
        $data.Time = @{ Source = $source; LastSync = $now.AddMinutes(-5).ToString('o'); LeapIndicator = 0; Stratum = 2
            Type = $type; TimeZone = 'Eastern Standard Time'; ParseSuccess = $true; Peers = 'fixture'; Raw = @(); Identity = 'TECHWORKS\audit' }
        $data.UserRead = @{ Context = 'SuppliedUser'; Identity = 'TECHWORKS\ordinary-reader'
            Reads = @(@{ Path = "\\$fqdn\SYSVOL"; Readable = $true; Error = $null },
                @{ Path = "\\$fqdn\NETLOGON"; Readable = $true; Error = $null },
                @{ Path = '\\techworks.local\SYSVOL'; Readable = $true; Error = $null }) }
        $data.MachineRead = @{ Context = 'Machine'; Identity = 'TECHWORKS\TW-CL00$'; Client = 'TW-CL00'; Target = $fqdn
            TimestampUtc = $now.AddMinutes(-10).ToString('o'); Reads = @(
                @{ Resource = 'SYSVOL'; Readable = $true }, @{ Resource = 'NETLOGON'; Readable = $true }, @{ Resource = 'PolicyFile'; Readable = $true }) }
        if ($t.Name -eq 'DC-02') { $data.Offset = @{ Samples = @(0.1, 0.2, 0.1, -0.2, 0.1); ExitCode = 0; Raw = @(); Identity = 'TECHWORKS\audit'; Observer = 'DC-02'; Destination = 'Techworks-DC01.techworks.local' } }
        foreach ($log in @('System', 'Directory Service', 'DNS Server', 'DFS Replication', 'Microsoft-Windows-GroupPolicy/Operational')) {
            $data['Events:' + $log] = @{ Log = $log; Enabled = $true; StartUtc = $now.AddHours(-24).ToString('o')
                EndUtc = $now.ToString('o'); OldestUtc = $now.AddDays(-7).ToString('o'); Truncated = $false; Events = @(); Identity = 'TECHWORKS\audit' }
        }
        foreach ($kind in $data.Keys) { $checks += @{ CheckId = ($t.Name + '/' + $kind); Result = @{ Success = $true; Evidence = $data[$kind]; Error = $null } } }
    }
    foreach ($client in @('TW-CL00', 'TW-CL01', 'TW-CL02')) {
        $checks += @{ CheckId = ($client + '/ClientDNS'); Result = @{ Success = $true; Error = $null
            Evidence = @{ Interfaces = @(@{ InterfaceAlias = 'Ethernet'; ServerAddresses = @('192.168.1.51', '192.168.1.60') }); Identity = 'TECHWORKS\audit' } } }
        $checks += @{ CheckId = ($client + '/Events:Microsoft-Windows-GroupPolicy/Operational'); Result = @{ Success = $true; Error = $null
            Evidence = @{ Log = 'Microsoft-Windows-GroupPolicy/Operational'; Enabled = $true; StartUtc = $now.AddDays(-1).ToString('o')
                EndUtc = $now.ToString('o'); OldestUtc = $now.AddDays(-7).ToString('o'); Truncated = $false; Events = @(); Identity = 'TECHWORKS\audit' } } }
    }
    @{ SchemaVersion = 1; NowUtc = $now.ToString('o'); Checks = $checks }
}
