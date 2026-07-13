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
