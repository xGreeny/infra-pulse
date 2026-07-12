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
