BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-InfraPulse orchestration' {
    It 'runs a local target without creating a remote session' {
        InModuleScope InfraPulse {
            Mock Test-InfraPulseLocalTarget { $true }
            Mock Invoke-InfraPulseTarget {
                param($Context, $Configuration, $Checks, $FailFast, $Tags)
                New-InfraPulseReport -RequestedComputerName $Context.RequestedComputerName -ComputerName $Context.ComputerName -Inventory $null -Results @(
                    New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName $Context.ComputerName -Target 'Memory' -Message 'Healthy.'
                ) -DurationMs 1 -Tags $Tags
            }
            Mock New-PSSession { throw 'New-PSSession must not be called for a local target.' }

            $report = Invoke-InfraPulse -ComputerName localhost -Check Memory -Tag ' production ', 'production', ''

            $report.OverallStatus | Should -Be 'Healthy'
            $report.Tags -join '|' | Should -Be 'production'
            Should -Invoke New-PSSession -Times 0 -Exactly
            Should -Invoke Invoke-InfraPulseTarget -Times 1 -Exactly
        }
    }

    It 'returns a connection-failure report when a remote session cannot open' {
        InModuleScope InfraPulse {
            Mock Test-InfraPulseLocalTarget { $false }
            Mock New-PSSessionOption { [pscustomobject]@{} }
            Mock New-PSSession { throw 'The client cannot connect.' }

            $report = Invoke-InfraPulse -ComputerName 'srv-offline-01' -Check Disk

            $report.OverallStatus | Should -Be 'Critical'
            $report.Results[0].CheckName | Should -Be 'Connection'
            $report.Results[0].Error | Should -Match 'cannot connect'
        }
    }

    It 'throws a connection error when FailFast is enabled' {
        InModuleScope InfraPulse {
            Mock Test-InfraPulseLocalTarget { $false }
            Mock New-PSSessionOption { [pscustomobject]@{} }
            Mock New-PSSession { throw 'The client cannot connect.' }

            { Invoke-InfraPulse -ComputerName 'srv-offline-01' -Check Disk -FailFast } | Should -Throw '*cannot connect*'
        }
    }

    It 'returns an execution-control report for an unexpected target failure' {
        InModuleScope InfraPulse {
            Mock Test-InfraPulseLocalTarget { $true }
            Mock Invoke-InfraPulseTarget { throw 'Unexpected orchestration failure.' }

            $report = Invoke-InfraPulse -ComputerName localhost -Check Memory

            $report.OverallStatus | Should -Be 'Unknown'
            $report.Results[0].CheckName | Should -Be 'Execution'
            $report.Results[0].Error | Should -Be 'Unexpected orchestration failure.'
        }
    }
}
