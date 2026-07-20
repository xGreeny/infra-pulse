$script:IsWindowsTarget = $env:OS -eq 'Windows_NT'

BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse check evaluation logic' {
    BeforeEach {
        InModuleScope InfraPulse {
            $script:Context = [pscustomobject]@{
                RequestedComputerName = 'SRV-TEST-01'
                ComputerName          = 'SRV-TEST-01'
                Session               = $null
                OwnsSession           = $false
            }
            $script:Defaults = Get-DefaultInfraPulseConfiguration
        }
    }

    It 'marks a disk critical when either critical capacity threshold is reached' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    DeviceId = 'C:'; VolumeName = 'System'; SizeBytes = 100GB; FreeBytes = 9GB
                    FreeGB = 9; FreePercent = 9; FileSystem = 'NTFS'
                }
            }

            $result = @(Invoke-InfraPulseDiskCheck -Context $script:Context -Settings $script:Defaults.Checks.Disk)
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'Critical'
            $result[0].Evidence.DeviceId | Should -Be 'C:'
        }
    }

    It 'marks available memory warning at the warning boundary' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    TotalBytes = 16GB; AvailableBytes = 3.2GB; TotalGB = 16
                    AvailableGB = 3.2; AvailablePercent = 20
                }
            }

            $result = Invoke-InfraPulseMemoryCheck -Context $script:Context -Settings $script:Defaults.Checks.Memory
            $result.Status | Should -Be 'Warning'
        }
    }

    It 'marks excessive uptime critical at the configured boundary' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    LastBootTime = (Get-Date).AddDays(-90)
                    UptimeDays   = 90
                    UptimeHours  = 2160
                }
            }

            $result = Invoke-InfraPulseUptimeCheck -Context $script:Context -Settings $script:Defaults.Checks.Uptime
            $result.Status | Should -Be 'Critical'
        }
    }

    It 'uses the configured pending-reboot severity' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{ Pending = $true; Reasons = @('Windows Update') }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.PendingReboot
            $settings.PendingStatus = 'Critical'

            $result = Invoke-InfraPulsePendingRebootCheck -Context $script:Context -Settings $settings
            $result.Status | Should -Be 'Critical'
            $result.WarningThreshold | Should -BeNullOrEmpty
            $result.CriticalThreshold | Should -Be 'Any supported reboot indicator'
            $result.Evidence.Reasons | Should -Contain 'Windows Update'
        }
    }

    It 'uses the configured service severity when a required service is absent' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'CriticalSvc'; DisplayName = 'CriticalSvc'; Status = 'NotFound'
                    StartMode = $null; Exists = $false
                }
            }
            $settings = [ordered]@{
                Enabled = $true
                Required = @(
                    [ordered]@{ Name = 'CriticalSvc'; ExpectedStatus = 'Running'; Severity = 'Critical' }
                )
            }

            $result = @(Invoke-InfraPulseServiceCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Critical'
            $result[0].ObservedValue | Should -Be 'NotFound'
            $result[0].WarningThreshold | Should -BeNullOrEmpty
            $result[0].CriticalThreshold | Should -Be 'Expected: Running'
        }
    }

    It 'identifies a certificate inside the critical renewal window' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                @(
                    [pscustomobject]@{ RecordType = 'Store'; StorePath = 'Cert:\LocalMachine\My'; Exists = $true }
                    [pscustomobject]@{
                        RecordType = 'Certificate'; StorePath = 'Cert:\LocalMachine\My'; Subject = 'CN=app.contoso.invalid'
                        Issuer = 'CN=Test CA'; Thumbprint = '00112233445566778899AABBCCDDEEFF00112233'
                        NotBefore = (Get-Date).AddDays(-300); NotAfter = (Get-Date).AddDays(10); DaysRemaining = 10
                        HasPrivateKey = $true; SerialNumber = '01'
                    }
                )
            }

            $result = @(Invoke-InfraPulseCertificateCheck -Context $script:Context -Settings $script:Defaults.Checks.Certificates)
            @($result | Where-Object Target -Like 'CN=app*')[0].Status | Should -Be 'Critical'
            @($result | Where-Object Target -EQ 'Certificate inventory')[0].Status | Should -Be 'Healthy'
        }
    }

    It 'marks an event log critical at the critical count boundary' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    LogName = 'System'; Exists = $true; QuerySucceeded = $true
                    Count = 100; RetrievedCount = 100; Truncated = $false
                    TopProviders = @(); Samples = @(); Error = $null
                }
            }

            $result = @(Invoke-InfraPulseEventLogCheck -Context $script:Context -Settings $script:Defaults.Checks.EventLog)
            $result[0].Status | Should -Be 'Critical'
        }
    }

    It 'marks a failed event-log query unknown' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    LogName = 'System'; Exists = $true; QuerySucceeded = $false
                    Count = 0; RetrievedCount = 0; Truncated = $false
                    TopProviders = @(); Samples = @(); Error = 'Access is denied.'
                }
            }

            $result = @(Invoke-InfraPulseEventLogCheck -Context $script:Context -Settings $script:Defaults.Checks.EventLog)
            $result[0].Status | Should -Be 'Unknown'
            $result[0].Error | Should -Be 'Access is denied.'
        }
    }

    It 'does not report a capped event-log query as healthy' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    LogName = 'System'; Exists = $true; QuerySucceeded = $true
                    Count = 1; RetrievedCount = 1000; Truncated = $true
                    TopProviders = @(); Samples = @(); Error = $null
                }
            }

            $result = @(Invoke-InfraPulseEventLogCheck -Context $script:Context -Settings $script:Defaults.Checks.EventLog)
            $result[0].Status | Should -Be 'Unknown'
            $result[0].Evidence.RetrievedCount | Should -Be 1000
        }
    }

    It 'marks successful DNS resolution healthy' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'login.microsoftonline.com'; QueryType = 'A'; Server = ''
                    Success = $true; Answers = @('20.190.128.1'); DurationMs = 8; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Dns
            $settings.Targets = @('login.microsoftonline.com')

            $result = @(Invoke-InfraPulseDnsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Healthy'
        }
    }

    It 'resolves CNAME-chained answers through the real scriptblock under module strict mode' {
        InModuleScope InfraPulse {
            # Stub so the mock also resolves on hosts without the DnsClient
            # module (Linux CI); the real scriptblock path must run locally
            # because only the module scope carries StrictMode.
            function script:Resolve-DnsName {
                [CmdletBinding()]
                param($Name, $Type, [switch]$DnsOnly, $Server)
            }
            Mock Resolve-DnsName {
                @(
                    [pscustomobject]@{ Name = 'login.microsoftonline.com'; QueryType = 'CNAME'; NameHost = 'ak.privatelink.msidentity.com' }
                    [pscustomobject]@{ Name = 'ak.privatelink.msidentity.com'; QueryType = 'A'; IPAddress = '20.190.128.1' }
                )
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Dns
            $settings.Targets = @('login.microsoftonline.com')

            $result = @(Invoke-InfraPulseDnsCheck -Context $script:Context -Settings $settings)

            $result[0].Status | Should -Be 'Healthy'
            $result[0].Error | Should -BeNullOrEmpty
            @($result[0].Evidence.Answers) | Should -Contain '20.190.128.1'
            @($result[0].Evidence.Answers) | Should -Contain 'ak.privatelink.msidentity.com'
        }
    }

    It 'marks an unsupported DNS query unknown instead of critical' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = '_ldap._tcp.dc._msdcs.contoso.invalid'; QueryType = 'SRV'; Server = ''
                    Success = $false; Answers = @(); DurationMs = 1; FailureKind = 'UnsupportedQuery'
                    Error = "Query type 'SRV' requires Resolve-DnsName on the target."
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Dns
            $settings.Targets = @(
                [ordered]@{ Name = '_ldap._tcp.dc._msdcs.contoso.invalid'; Type = 'SRV' }
            )

            $result = @(Invoke-InfraPulseDnsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Unknown'
            $result[0].CriticalThreshold | Should -BeNullOrEmpty
            $result[0].Evidence.FailureKind | Should -Be 'UnsupportedQuery'
        }
    }

    It 'marks a failed TCP endpoint critical' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'LDAP'; Host = 'dc01.contoso.invalid'; Port = 389
                    Success = $false; DurationMs = 3000; TimeoutMs = 3000; Error = 'Timed out.'
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tcp
            $settings.Endpoints = @(
                [ordered]@{ Name = 'LDAP'; Host = 'dc01.contoso.invalid'; Port = 389 }
            )

            $result = @(Invoke-InfraPulseTcpCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Critical'
            $result[0].Error | Should -Be 'Timed out.'
        }
    }

    It 'evaluates disk thresholds against unrounded byte counts' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                # 20.004 GB free of 200 GB: the rounded display value (20.0) sits on
                # the warning boundary but the exact value is above it.
                [pscustomobject]@{
                    DeviceId = 'D:'; VolumeName = 'Data'; SizeBytes = 200GB; FreeBytes = 21478887587
                    FreeGB = 20; FreePercent = 10; FileSystem = 'NTFS'
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Disk
            $settings.WarningFreePercent = 10
            $settings.CriticalFreePercent = 5
            $settings.WarningFreeGB = 20
            $settings.CriticalFreeGB = 10

            $result = @(Invoke-InfraPulseDiskCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Healthy'
        }
    }

    It 'keeps a failed service query unknown instead of reporting a missing service' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'CriticalSvc'; DisplayName = 'CriticalSvc'; Status = 'QueryFailed'
                    StartMode = $null; Exists = $false; QuerySucceeded = $false; Error = 'Access is denied.'
                }
            }
            $settings = [ordered]@{
                Enabled = $true
                Required = @(
                    [ordered]@{ Name = 'CriticalSvc'; ExpectedStatus = 'Running'; Severity = 'Critical' }
                )
            }

            $result = @(Invoke-InfraPulseServiceCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Unknown'
            $result[0].Error | Should -Be 'Access is denied.'
        }
    }

    It 'reports a missing configured certificate store as unknown' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                @(
                    [pscustomobject]@{ RecordType = 'Store'; StorePath = 'Cert:\LocalMachine\My'; Exists = $true }
                    [pscustomobject]@{ RecordType = 'Store'; StorePath = 'Cert:\LocalMachine\WebHosting'; Exists = $false }
                )
            }

            $result = @(Invoke-InfraPulseCertificateCheck -Context $script:Context -Settings $script:Defaults.Checks.Certificates)
            $missing = @($result | Where-Object Target -EQ 'Cert:\LocalMachine\WebHosting')
            $missing.Count | Should -Be 1
            $missing[0].Status | Should -Be 'Unknown'
            @($result | Where-Object Target -EQ 'Certificate inventory')[0].Status | Should -Be 'Healthy'
        }
    }

    It 'marks a healthy TLS endpoint healthy with protocol evidence' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'Portal'; Host = 'portal.contoso.invalid'; Port = 443; Sni = 'portal.contoso.invalid'
                    HandshakeSucceeded = $true; Protocol = 'Tls13'; Subject = 'CN=portal.contoso.invalid'
                    Issuer = 'CN=Contoso CA'; Thumbprint = 'AA00'; SerialNumber = '01'
                    NotBefore = (Get-Date).AddDays(-30); NotAfter = (Get-Date).AddDays(200); DaysRemaining = 200
                    NameMatch = $true; ChainTrusted = $true; ChainStatus = @(); PolicyErrors = 'None'
                    DurationMs = 42; TimeoutMs = 5000; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tls
            $settings.Endpoints = @([ordered]@{ Name = 'Portal'; Host = 'portal.contoso.invalid' })

            $result = @(Invoke-InfraPulseTlsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Healthy'
            $result[0].Evidence.Protocol | Should -Be 'Tls13'
        }
    }

    It 'marks an untrusted TLS chain critical when trust is required' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'Portal'; Host = 'portal.contoso.invalid'; Port = 443; Sni = 'portal.contoso.invalid'
                    HandshakeSucceeded = $true; Protocol = 'Tls12'; Subject = 'CN=portal.contoso.invalid'
                    Issuer = 'CN=Untrusted CA'; Thumbprint = 'AA01'; SerialNumber = '02'
                    NotBefore = (Get-Date).AddDays(-30); NotAfter = (Get-Date).AddDays(200); DaysRemaining = 200
                    NameMatch = $true; ChainTrusted = $false; ChainStatus = @('UntrustedRoot: The root is not trusted.')
                    PolicyErrors = 'RemoteCertificateChainErrors'; DurationMs = 40; TimeoutMs = 5000; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tls
            $settings.Endpoints = @([ordered]@{ Name = 'Portal'; Host = 'portal.contoso.invalid' })

            $result = @(Invoke-InfraPulseTlsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Critical'
            $result[0].Message | Should -Match 'chain is not trusted'
        }
    }

    It 'tolerates an untrusted TLS chain when trust is not required' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'Portal'; Host = 'portal.contoso.invalid'; Port = 443; Sni = 'portal.contoso.invalid'
                    HandshakeSucceeded = $true; Protocol = 'Tls12'; Subject = 'CN=portal.contoso.invalid'
                    Issuer = 'CN=Internal CA'; Thumbprint = 'AA02'; SerialNumber = '03'
                    NotBefore = (Get-Date).AddDays(-30); NotAfter = (Get-Date).AddDays(200); DaysRemaining = 200
                    NameMatch = $true; ChainTrusted = $false; ChainStatus = @('UntrustedRoot: The root is not trusted.')
                    PolicyErrors = 'RemoteCertificateChainErrors'; DurationMs = 40; TimeoutMs = 5000; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tls
            $settings.RequireTrustedChain = $false
            $settings.Endpoints = @([ordered]@{ Name = 'Portal'; Host = 'portal.contoso.invalid' })

            $result = @(Invoke-InfraPulseTlsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Healthy'
        }
    }

    It 'marks a failed TLS handshake critical' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'Portal'; Host = 'portal.contoso.invalid'; Port = 443; Sni = 'portal.contoso.invalid'
                    HandshakeSucceeded = $false; Protocol = $null; Subject = $null
                    Issuer = $null; Thumbprint = $null; SerialNumber = $null
                    NotBefore = $null; NotAfter = $null; DaysRemaining = $null
                    NameMatch = $false; ChainTrusted = $false; ChainStatus = @(); PolicyErrors = ''
                    DurationMs = 5000; TimeoutMs = 5000; Error = 'Connection timed out after 5000 ms.'
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tls
            $settings.Endpoints = @([ordered]@{ Name = 'Portal'; Host = 'portal.contoso.invalid' })

            $result = @(Invoke-InfraPulseTlsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Critical'
            $result[0].Error | Should -Match 'timed out'
        }
    }

    It 'marks a TLS certificate inside the warning window as warning' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Name = 'Portal'; Host = 'portal.contoso.invalid'; Port = 443; Sni = 'portal.contoso.invalid'
                    HandshakeSucceeded = $true; Protocol = 'Tls13'; Subject = 'CN=portal.contoso.invalid'
                    Issuer = 'CN=Contoso CA'; Thumbprint = 'AA03'; SerialNumber = '04'
                    NotBefore = (Get-Date).AddDays(-340); NotAfter = (Get-Date).AddDays(25); DaysRemaining = 25
                    NameMatch = $true; ChainTrusted = $true; ChainStatus = @(); PolicyErrors = 'None'
                    DurationMs = 42; TimeoutMs = 5000; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Tls
            $settings.Endpoints = @([ordered]@{ Name = 'Portal'; Host = 'portal.contoso.invalid' })

            $result = @(Invoke-InfraPulseTlsCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Warning'
        }
    }

    It 'marks excessive SNTP offset warning' {
        InModuleScope InfraPulse {
            Mock Invoke-InfraPulseCommand {
                [pscustomobject]@{
                    Server = 'time.windows.com'; Address = '20.101.57.9'; Success = $true
                    OffsetSeconds = 3; AbsoluteOffsetSeconds = 3; RoundTripMilliseconds = 25
                    Stratum = 2; Version = 4; Mode = 4; DurationMs = 26; Error = $null
                }
            }
            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.TimeSync
            $settings.Enabled = $true

            $result = @(Invoke-InfraPulseTimeSyncCheck -Context $script:Context -Settings $settings)
            $result[0].Status | Should -Be 'Warning'
        }
    }
}

Describe 'InfraPulse certificate store filtering' -Skip:(-not $script:IsWindowsTarget) {
    BeforeAll {
        InModuleScope InfraPulse {
            function script:New-InfraPulseTestCertificate {
                param(
                    [Parameter(Mandatory)]
                    [string]$Subject,

                    [Parameter(Mandatory)]
                    [datetime]$NotBefore,

                    [Parameter(Mandatory)]
                    [datetime]$NotAfter,

                    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Issuer
                )

                $key = [System.Security.Cryptography.ECDsa]::Create()
                try {
                    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                        $Subject,
                        $key,
                        [System.Security.Cryptography.HashAlgorithmName]::SHA256)

                    if ($PSBoundParameters.ContainsKey('Issuer')) {
                        return $request.Create($Issuer, $NotBefore, $NotAfter, [byte[]]@(1, 2, 3, 4, 5, 6, 7, 8))
                    }

                    $request.CertificateExtensions.Add(
                        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true))
                    return $request.CreateSelfSigned($NotBefore, $NotAfter)
                }
                finally {
                    $key.Dispose()
                }
            }
        }
    }

    BeforeEach {
        InModuleScope InfraPulse {
            $script:Context = [pscustomobject]@{
                RequestedComputerName = 'SRV-TEST-01'
                ComputerName          = 'SRV-TEST-01'
                Session               = $null
                OwnsSession           = $false
            }
            $script:Defaults = Get-DefaultInfraPulseConfiguration
        }
    }

    It 'excludes certificates whose issuer matches IssuerExcludePatterns' {
        InModuleScope InfraPulse {
            $authority = New-InfraPulseTestCertificate -Subject 'CN=MS-Organization-P2P-Access [2026]' -NotBefore (Get-Date).AddDays(-10) -NotAfter (Get-Date).AddDays(365)
            $script:StoreCertificates = @(
                New-InfraPulseTestCertificate -Subject 'CN=11111111-2222-3333-4444-555555555555' -NotBefore (Get-Date).AddHours(-1) -NotAfter (Get-Date).AddHours(23) -Issuer $authority
                New-InfraPulseTestCertificate -Subject 'CN=app.contoso.invalid' -NotBefore (Get-Date).AddDays(-30) -NotAfter (Get-Date).AddDays(300)
            )
            Mock Test-Path { $true }
            Mock Get-ChildItem { $script:StoreCertificates }

            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Certificates
            $settings.StorePaths = @('Cert:\LocalMachine\My')
            $settings.IssuerExcludePatterns = @('CN=MS-Organization-P2P-Access*')

            $result = @(Invoke-InfraPulseCertificateCheck -Context $script:Context -Settings $settings)

            @($result | Where-Object Status -In @('Warning', 'Critical')).Count | Should -Be 0
            $summary = @($result | Where-Object Target -EQ 'Certificate inventory')[0]
            $summary.Evidence.TotalCertificates | Should -Be 1
            $summary.Evidence.HealthyCertificates | Should -Be 1
        }
    }

    It 'excludes certificates whose total lifetime is below MinTotalLifetimeDays' {
        InModuleScope InfraPulse {
            $script:StoreCertificates = @(
                New-InfraPulseTestCertificate -Subject 'CN=RDSAGENT.WVD' -NotBefore (Get-Date).AddDays(-1) -NotAfter (Get-Date).AddDays(25)
                New-InfraPulseTestCertificate -Subject 'CN=app.contoso.invalid' -NotBefore (Get-Date).AddDays(-30) -NotAfter (Get-Date).AddDays(300)
            )
            Mock Test-Path { $true }
            Mock Get-ChildItem { $script:StoreCertificates }

            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Certificates
            $settings.StorePaths = @('Cert:\LocalMachine\My')
            $settings.MinTotalLifetimeDays = 27

            $result = @(Invoke-InfraPulseCertificateCheck -Context $script:Context -Settings $settings)

            @($result | Where-Object Status -In @('Warning', 'Critical')).Count | Should -Be 0
            $summary = @($result | Where-Object Target -EQ 'Certificate inventory')[0]
            $summary.Evidence.TotalCertificates | Should -Be 1
            $summary.Evidence.HealthyCertificates | Should -Be 1
        }
    }

    It 'still reports a short-lived certificate when no lifetime filter is configured' {
        InModuleScope InfraPulse {
            $script:StoreCertificates = @(
                New-InfraPulseTestCertificate -Subject 'CN=RDSAGENT.WVD' -NotBefore (Get-Date).AddDays(-1) -NotAfter (Get-Date).AddDays(25)
            )
            Mock Test-Path { $true }
            Mock Get-ChildItem { $script:StoreCertificates }

            $settings = Copy-InfraPulseValue -Value $script:Defaults.Checks.Certificates
            $settings.StorePaths = @('Cert:\LocalMachine\My')

            $result = @(Invoke-InfraPulseCertificateCheck -Context $script:Context -Settings $settings)

            @($result | Where-Object Target -Like 'CN=RDSAGENT.WVD*')[0].Status | Should -Be 'Warning'
        }
    }
}
