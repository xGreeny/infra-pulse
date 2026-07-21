BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse object contract' {
    It 'creates a typed result with stable schema fields' {
        InModuleScope InfraPulse {
            $result = New-InfraPulseResult -Status Warning -CheckName Disk -Category Capacity -ComputerName 'SRV-01' -Target 'C:' -Message 'Low space.' -ObservedValue 15 -WarningThreshold 20 -CriticalThreshold 10 -Recommendation 'Review capacity.' -Evidence @{ FreePercent = 15 } -DurationMs 12.345

            $result.PSObject.TypeNames[0] | Should -Be 'InfraPulse.Result'
            $result.SchemaVersion | Should -Be '1.0'
            $result.Status | Should -Be 'Warning'
            $result.DurationMs | Should -Be 12.35
            $result.TimestampUtc.Kind | Should -Be ([DateTimeKind]::Utc)
            $result.Evidence.FreePercent | Should -Be 15
        }
    }

    It 'uses deterministic report-status precedence' {
        InModuleScope InfraPulse {
            $computer = 'SRV-01'
            $healthy = New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName $computer -Target 'Memory' -Message 'Healthy.'
            $unknown = New-InfraPulseResult -Status Unknown -CheckName Dns -Category Connectivity -ComputerName $computer -Target 'dns' -Message 'Unknown.'
            $warning = New-InfraPulseResult -Status Warning -CheckName Disk -Category Capacity -ComputerName $computer -Target 'C:' -Message 'Warning.'
            $critical = New-InfraPulseResult -Status Critical -CheckName Services -Category Availability -ComputerName $computer -Target 'svc' -Message 'Critical.'

            (Get-InfraPulseSummary -Results @($healthy)).OverallStatus | Should -Be 'Healthy'
            (Get-InfraPulseSummary -Results @($healthy, $unknown)).OverallStatus | Should -Be 'Unknown'
            (Get-InfraPulseSummary -Results @($healthy, $unknown, $warning)).OverallStatus | Should -Be 'Warning'
            (Get-InfraPulseSummary -Results @($healthy, $unknown, $warning, $critical)).OverallStatus | Should -Be 'Critical'
        }
    }

    It 'creates a typed report with counts, tags, inventory, and timing' {
        InModuleScope InfraPulse {
            $results = @(
                New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName 'SRV-01' -Target 'Memory' -Message 'Healthy.'
                New-InfraPulseResult -Status Warning -CheckName Disk -Category Capacity -ComputerName 'SRV-01' -Target 'C:' -Message 'Warning.'
            )
            $inventory = [pscustomobject]@{ ComputerName = 'SRV-01'; Platform = 'Windows' }
            $report = New-InfraPulseReport -RequestedComputerName 'srv-01.contoso.invalid' -ComputerName 'SRV-01' -Inventory $inventory -Results $results -DurationMs 42.8 -Tags @('production', 'app')

            $report.PSObject.TypeNames[0] | Should -Be 'InfraPulse.Report'
            $report.OverallStatus | Should -Be 'Warning'
            $report.Summary.Total | Should -Be 2
            $report.Summary.Healthy | Should -Be 1
            $report.Summary.Warning | Should -Be 1
            $report.Tags -join '|' | Should -Be 'production|app'
            $report.Inventory.Platform | Should -Be 'Windows'
            $report.DurationMs | Should -Be 42.8
        }
    }

    It 'stamps schema 1.3 run metadata onto every report' {
        InModuleScope InfraPulse {
            $results = @(
                New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName 'SRV-01' -Target 'Memory' -Message 'Healthy.'
            )
            $report = New-InfraPulseReport -RequestedComputerName 'srv-01' -ComputerName 'SRV-01' -Inventory $null -Results $results -DurationMs 10 -RunId 'f0e1d2c3-0000-4000-8000-000000000001' -ConfigurationFingerprint 'abc123' -ConfigurationSource 'Built-in defaults' -EnvironmentName 'Kunde Demo'

            $report.SchemaVersion | Should -Be '1.3'
            $report.RunId | Should -Be 'f0e1d2c3-0000-4000-8000-000000000001'
            $report.ConfigurationFingerprint | Should -Be 'abc123'
            $report.ConfigurationSource | Should -Be 'Built-in defaults'
            $report.EnvironmentName | Should -Be 'Kunde Demo'
            $report.StartedAtUtc.Kind | Should -Be ([DateTimeKind]::Utc)
            $report.CompletedAtUtc.Kind | Should -Be ([DateTimeKind]::Utc)
            $report.CompletedAtUtc | Should -BeGreaterOrEqual $report.StartedAtUtc

            $second = New-InfraPulseReport -RequestedComputerName 'srv-01' -ComputerName 'SRV-01' -Inventory $null -Results $results -DurationMs 10
            $second.RunId | Should -Not -BeNullOrEmpty
        }
    }

    It 'produces identical configuration fingerprints for logically equal configurations' {
        InModuleScope InfraPulse {
            $first = Get-InfraPulseConfigurationFingerprint -Configuration (Get-DefaultInfraPulseConfiguration)
            $second = Get-InfraPulseConfigurationFingerprint -Configuration (Get-DefaultInfraPulseConfiguration)
            $changed = (Resolve-InfraPulseConfiguration -Configuration @{ Checks = @{ Disk = @{ WarningFreePercent = 19 } } }).Configuration

            $first | Should -Match '^[0-9a-f]{64}$'
            $first | Should -Be $second
            (Get-InfraPulseConfigurationFingerprint -Configuration $changed) | Should -Not -Be $first
        }
    }

    It 'normalizes DateTime values to round-trip UTC strings for serialization' {
        InModuleScope InfraPulse {
            $utc = [datetime]::new(2026, 7, 11, 9, 30, 0, [DateTimeKind]::Utc)
            $local = [datetime]::new(2026, 7, 1, 6, 15, 30, [DateTimeKind]::Local)
            $value = [pscustomobject]@{
                GeneratedAtUtc = $utc
                Inventory      = [pscustomobject]@{ CollectedAtUtc = $utc }
                Evidence       = [ordered]@{
                    LastBootTime = $local
                    Nested       = @(@{ TimeCreated = $utc }, 'text', 42)
                }
            }

            $normalized = ConvertTo-InfraPulseSerializableValue -Value $value

            $normalized.GeneratedAtUtc | Should -Be '2026-07-11T09:30:00.0000000Z'
            $normalized.Inventory.CollectedAtUtc | Should -Be '2026-07-11T09:30:00.0000000Z'
            $normalized.Evidence.LastBootTime | Should -Be $local.ToUniversalTime().ToString('o')
            $normalized.Evidence.Nested[0].TimeCreated | Should -Be '2026-07-11T09:30:00.0000000Z'
            $normalized.Evidence.Nested[1] | Should -Be 'text'
            $normalized.Evidence.Nested[2] | Should -Be 42

            $value.GeneratedAtUtc | Should -BeOfType [datetime]
            ConvertTo-Json -InputObject $normalized -Depth 8 | Should -Not -Match '/Date\('
        }
    }

    It 'represents a connection failure as a complete report' {
        InModuleScope InfraPulse {
            $report = New-InfraPulseConnectionFailureReport -ComputerName 'srv-offline-01' -ErrorMessage 'Connection refused.' -DurationMs 500

            $report.OverallStatus | Should -Be 'Critical'
            $report.Results.Count | Should -Be 1
            $report.Results[0].CheckName | Should -Be 'Connection'
            $report.Results[0].Error | Should -Be 'Connection refused.'
        }
    }
}
