BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
    $env:INFRAPULSE_CONFIG = $null
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

    It 'rejects an empty pending-reboot exclusion pattern' {
        $result = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                PendingReboot = @{
                    ExcludeReasons = @('Pending file rename operations', '   ')
                }
            }
        }

        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'PendingReboot\.ExcludeReasons'
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
            $resolved = Resolve-InfraPulseConfiguration -Configuration @{
                Checks = @{
                    Disk = @{
                        WarningFreePercent = 17
                    }
                }
            }

            $resolved.Source | Should -Be 'Inline configuration'
            $resolved.Configuration.Checks.Disk.WarningFreePercent | Should -Be 17
            $resolved.Configuration.Checks.Disk.CriticalFreePercent | Should -Be 10
            $resolved.Configuration.Checks.Memory.Enabled | Should -BeTrue
            $resolved.Configuration.General.ConnectionTimeoutSeconds | Should -Be 15
        }
    }

    It 'falls back to built-in defaults when nothing is discovered' {
        InModuleScope InfraPulse -Parameters @{ WorkDir = (Join-Path $TestDrive 'empty-cwd') } {
            param($WorkDir)
            $null = New-Item -Path $WorkDir -ItemType Directory -Force
            Push-Location -LiteralPath $WorkDir
            try {
                $resolved = Resolve-InfraPulseConfiguration
                $resolved.Source | Should -Be 'Built-in defaults'
                $resolved.Configuration.Checks.Disk.WarningFreePercent | Should -Be 20
            }
            finally {
                Pop-Location
            }
        }
    }

    It 'discovers configuration from the INFRAPULSE_CONFIG environment variable' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'env-config.psd1'
        Set-Content -LiteralPath $configPath -Encoding UTF8 -Value "@{ SchemaVersion = '1.0'; Checks = @{ Disk = @{ WarningFreePercent = 19 } } }"

        InModuleScope InfraPulse -Parameters @{ ConfigPath = $configPath } {
            param($ConfigPath)
            $env:INFRAPULSE_CONFIG = $ConfigPath
            try {
                $resolved = Resolve-InfraPulseConfiguration
                $resolved.Source | Should -Match 'INFRAPULSE_CONFIG'
                $resolved.Configuration.Checks.Disk.WarningFreePercent | Should -Be 19
            }
            finally {
                $env:INFRAPULSE_CONFIG = $null
            }
        }
    }

    It 'discovers an infra-pulse.psd1 from the working directory' {
        $workDir = Join-Path -Path $TestDrive -ChildPath 'cwd-discovery'
        $null = New-Item -Path $workDir -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $workDir 'infra-pulse.psd1') -Encoding UTF8 -Value "@{ SchemaVersion = '1.0'; Checks = @{ Disk = @{ WarningFreePercent = 18 } } }"

        InModuleScope InfraPulse -Parameters @{ WorkDir = $workDir } {
            param($WorkDir)
            Push-Location -LiteralPath $WorkDir
            try {
                $resolved = Resolve-InfraPulseConfiguration
                $resolved.Source | Should -Match 'Working directory'
                $resolved.Configuration.Checks.Disk.WarningFreePercent | Should -Be 18
            }
            finally {
                Pop-Location
            }
        }
    }

    It 'prefers an explicit path over discovery' {
        $envConfig = Join-Path -Path $TestDrive -ChildPath 'env-loses.psd1'
        Set-Content -LiteralPath $envConfig -Encoding UTF8 -Value "@{ SchemaVersion = '1.0'; Checks = @{ Disk = @{ WarningFreePercent = 11 } } }"
        $explicitConfig = Join-Path -Path $TestDrive -ChildPath 'explicit-wins.psd1'
        Set-Content -LiteralPath $explicitConfig -Encoding UTF8 -Value "@{ SchemaVersion = '1.0'; Checks = @{ Disk = @{ WarningFreePercent = 12 } } }"

        InModuleScope InfraPulse -Parameters @{ EnvConfig = $envConfig; ExplicitConfig = $explicitConfig } {
            param($EnvConfig, $ExplicitConfig)
            $env:INFRAPULSE_CONFIG = $EnvConfig
            try {
                $resolved = Resolve-InfraPulseConfiguration -ConfigurationPath $ExplicitConfig
                $resolved.Source | Should -Match 'Parameter'
                $resolved.Configuration.Checks.Disk.WarningFreePercent | Should -Be 12
            }
            finally {
                $env:INFRAPULSE_CONFIG = $null
            }
        }
    }

    It 'throws when INFRAPULSE_CONFIG points to a missing file' {
        InModuleScope InfraPulse {
            $env:INFRAPULSE_CONFIG = 'C:\does\not\exist\infra-pulse.psd1'
            try {
                { Resolve-InfraPulseConfiguration } | Should -Throw '*INFRAPULSE_CONFIG*'
            }
            finally {
                $env:INFRAPULSE_CONFIG = $null
            }
        }
    }

    It 'defaults and validates the PatchAge thresholds' {
        $result = Test-InfraPulseConfiguration -Configuration @{}

        $result.IsValid | Should -BeTrue
        $result.EffectiveConfiguration.Checks.PatchAge.WarningDays | Should -Be 45
        $result.EffectiveConfiguration.Checks.PatchAge.CriticalDays | Should -Be 90

        $inverted = Test-InfraPulseConfiguration -Configuration @{
            Checks = @{
                PatchAge = @{
                    WarningDays  = 90
                    CriticalDays = 45
                }
            }
        }
        $inverted.IsValid | Should -BeFalse
        ($inverted.Errors -join ' ') | Should -Match 'PatchAge\.CriticalDays'
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
