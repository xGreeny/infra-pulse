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

Describe 'Local Windows integration scan' -Tag 'Integration' -Skip:(-not $script:IsWindowsTarget) {
    It 'collects inventory and core Windows health results' {
        $report = Invoke-InfraPulse -ComputerName localhost -Check Disk, Memory, Uptime, PendingReboot -FailFast

        $report.PSObject.TypeNames | Should -Contain 'InfraPulse.Report'
        $report.ComputerName | Should -Not -BeNullOrEmpty
        $report.Inventory.Platform | Should -Be 'Windows'
        @($report.Results).Count | Should -BeGreaterOrEqual 4
        @($report.Results.CheckName) | Should -Contain 'Disk'
        @($report.Results.CheckName) | Should -Contain 'Memory'
        @($report.Results.CheckName) | Should -Contain 'Uptime'
        @($report.Results.CheckName) | Should -Contain 'PendingReboot'
        $report.OverallStatus | Should -BeIn @('Healthy', 'Warning', 'Critical', 'Unknown')
    }

    It 'exports the live report to all supported formats' {
        $report = Invoke-InfraPulse -ComputerName localhost -Check Disk, Memory -FailFast
        $html = Join-Path -Path $TestDrive -ChildPath 'integration.html'
        $json = Join-Path -Path $TestDrive -ChildPath 'integration.json'
        $csv = Join-Path -Path $TestDrive -ChildPath 'integration.csv'

        $report | Export-InfraPulseReport -Path $html -Force
        $report | Export-InfraPulseReport -Path $json -Force
        $report | Export-InfraPulseReport -Path $csv -Force

        Test-Path -LiteralPath $html | Should -BeTrue
        Test-Path -LiteralPath $json | Should -BeTrue
        Test-Path -LiteralPath $csv | Should -BeTrue
    }
}
