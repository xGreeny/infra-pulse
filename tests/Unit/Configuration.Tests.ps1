BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse configuration lifecycle' {
    It 'creates and validates the full configuration template' {
        $path = Join-Path -Path $TestDrive -ChildPath 'infra-pulse.full.psd1'
        $file = New-InfraPulseConfiguration -Path $path -PassThru

        $file.FullName | Should -Be $path
        Test-Path -LiteralPath $path | Should -BeTrue
        Test-InfraPulseConfiguration -Path $path -Quiet | Should -BeTrue
    }

    It 'creates and validates the minimal override template' {
        $path = Join-Path -Path $TestDrive -ChildPath 'infra-pulse.minimal.psd1'
        New-InfraPulseConfiguration -Path $path -Minimal

        Test-InfraPulseConfiguration -Path $path -Quiet | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw) | Should -Match "DefaultChecks = @\('Disk', 'Memory', 'Uptime', 'PendingReboot'\)"
    }

    It 'does not overwrite a configuration unless Force is supplied' {
        $path = Join-Path -Path $TestDrive -ChildPath 'existing.psd1'
        Set-Content -LiteralPath $path -Value '@{}'

        { New-InfraPulseConfiguration -Path $path } | Should -Throw '*Use -Force*'
        { New-InfraPulseConfiguration -Path $path -Force } | Should -Not -Throw
    }

    It 'rejects an invalid file extension' {
        { New-InfraPulseConfiguration -Path (Join-Path $TestDrive 'config.json') } | Should -Throw '*.psd1*'
    }

    It 'rejects inverted disk thresholds' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Disk = @{
                    WarningFreePercent  = 10
                    CriticalFreePercent = 20
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'CriticalFreePercent'
    }

    It 'rejects invalid per-target DNS record types' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Dns = @{
                    Targets = @(
                        @{ Name = 'example.invalid'; Type = 'HTTP' }
                    )
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'invalid query type'
    }

    It 'accepts certificate issuer exclude patterns and a minimum lifetime' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Certificates = @{
                    IssuerExcludePatterns = @('CN=MS-Organization-P2P-Access*')
                    MinTotalLifetimeDays  = 27
                }
            }
        }

        $result.IsValid | Should -BeTrue
        $result.EffectiveConfiguration.Checks.Certificates.IssuerExcludePatterns | Should -Be @('CN=MS-Organization-P2P-Access*')
        $result.EffectiveConfiguration.Checks.Certificates.MinTotalLifetimeDays | Should -Be 27
    }

    It 'defaults the certificate issuer patterns and minimum lifetime' {
        $result = Test-InfraPulseConfiguration -Configuration @{}

        $result.IsValid | Should -BeTrue
        @($result.EffectiveConfiguration.Checks.Certificates.IssuerExcludePatterns).Count | Should -Be 0
        $result.EffectiveConfiguration.Checks.Certificates.MinTotalLifetimeDays | Should -Be 0
    }

    It 'rejects an empty certificate issuer exclude pattern' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Certificates = @{
                    IssuerExcludePatterns = @('CN=MS-Organization-P2P-Access*', '   ')
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'IssuerExcludePatterns'
    }

    It 'rejects a non-Boolean rotation handling switch' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Certificates = @{
                    TreatShortLivedAsRotating = 'yes'
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'TreatShortLivedAsRotating'
    }

    It 'rejects a negative certificate minimum lifetime' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Certificates = @{
                    MinTotalLifetimeDays = -1
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'MinTotalLifetimeDays'
    }

    It 'defaults the Tls check to enabled with safe thresholds' {
        $result = Test-InfraPulseConfiguration -Configuration @{}

        $result.IsValid | Should -BeTrue
        $result.EffectiveConfiguration.Checks.Tls.Enabled | Should -BeTrue
        $result.EffectiveConfiguration.Checks.Tls.WarningDays | Should -Be 30
        $result.EffectiveConfiguration.Checks.Tls.CriticalDays | Should -Be 14
        $result.EffectiveConfiguration.Checks.Tls.RequireTrustedChain | Should -BeTrue
        $result.EffectiveConfiguration.Checks.Tls.RequireNameMatch | Should -BeTrue
        @($result.EffectiveConfiguration.Checks.Tls.Endpoints).Count | Should -Be 0
    }

    It 'rejects a Tls endpoint without a host' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Tls = @{
                    Endpoints = @(
                        @{ Name = 'Portal'; Port = 443 }
                    )
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'Tls\.Endpoints\[0\]\.Host'
    }

    It 'rejects inverted Tls expiry thresholds' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                Tls = @{
                    WarningDays  = 10
                    CriticalDays = 20
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'Tls\.CriticalDays'
    }

    It 'rejects an unsafe TimeSync timeout' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                TimeSync = @{
                    TimeoutMilliseconds = 0
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'between 100 and 60000'
    }

    It 'preserves defaults while applying a partial override' {
        InModuleScope InfraPulse {
            $configuration = Resolve-InfraPulseConfiguration -Configuration @{
                Checks = @{
                    Disk = @{
                        WarningFreePercent = 17
                    }
                }
            }

            $configuration.Checks.Disk.WarningFreePercent | Should -Be 17
            $configuration.Checks.Disk.CriticalFreePercent | Should -Be 10
            $configuration.Checks.Memory.Enabled | Should -BeTrue
            $configuration.General.ConnectionTimeoutSeconds | Should -Be 15
        }
    }

    It 'returns warnings without invalidating unknown check sections' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                CustomProbe = @{ Enabled = $true }
            }
        }

        $result.IsValid | Should -BeTrue
        ($result.Warnings -join ' ') | Should -Match 'CustomProbe'
    }
}
