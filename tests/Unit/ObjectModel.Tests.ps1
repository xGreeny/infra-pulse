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
