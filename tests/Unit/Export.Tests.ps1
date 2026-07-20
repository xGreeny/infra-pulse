BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop

    $script:Report = InModuleScope InfraPulse {
        $results = @(
            New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName 'SRV-DEMO-01' -Target 'Physical memory' -Message '12.50 GB available.' -ObservedValue '39.06%' -WarningThreshold '<= 20%' -CriticalThreshold '<= 10%' -Evidence @{ AvailableGB = 12.5; LastBootTime = [datetime]::new(2026, 7, 1, 6, 15, 30, [DateTimeKind]::Utc) }
            New-InfraPulseResult -Status Warning -CheckName Disk -Category Capacity -ComputerName 'SRV-DEMO-01' -Target '<script>alert(1)</script>' -Message '18.00 GB free.' -ObservedValue '18%' -WarningThreshold '<= 20%' -CriticalThreshold '<= 10%' -Recommendation 'Review capacity.' -Evidence @{ DeviceId = 'C:' }
        )
        $inventory = [pscustomobject]@{
            OperatingSystem = 'Microsoft Windows Server 2022 Standard'; Version = '10.0.20348'; BuildNumber = '20348'
            Architecture = '64-bit'; Fqdn = 'srv-demo-01.contoso.invalid'; Manufacturer = 'VMware, Inc.'
            Model = 'VMware Virtual Platform'; Domain = 'contoso.invalid'; PowerShellEdition = 'Core'; PowerShellVersion = '7.6.3'
            CollectedAtUtc = [datetime]::new(2026, 7, 11, 9, 29, 55, [DateTimeKind]::Utc)
        }
        New-InfraPulseReport -RequestedComputerName 'srv-demo-01' -ComputerName 'SRV-DEMO-01' -Inventory $inventory -Results $results -DurationMs 120 -Tags @('demo')
    }
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse report export' {
    It 'writes a self-contained searchable HTML report with encoded values' {
        $path = Join-Path -Path $TestDrive -ChildPath 'report.html'
        $file = $script:Report | Export-InfraPulseReport -Path $path -Force -PassThru
        $content = Get-Content -LiteralPath $file.FullName -Raw

        $content | Should -Match '<!doctype html>'
        $content | Should -Match 'filter-query'
        $content | Should -Match 'InfraPulse 1.1.0'
        $content | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $content | Should -Not -Match '<script>alert\(1\)</script>'
        $content | Should -Not -Match '<link[^>]+stylesheet'
        $content | Should -Not -Match '<script[^>]+src='
    }

    It 'emits no pipeline output unless PassThru is requested' {
        $path = Join-Path -Path $TestDrive -ChildPath 'silent-report.json'
        $output = @($script:Report | Export-InfraPulseReport -Path $path -Force)

        $output | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'writes a structured JSON array' {
        $path = Join-Path -Path $TestDrive -ChildPath 'report.json'
        $script:Report | Export-InfraPulseReport -Path $path -Force
        $data = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)

        $data.Count | Should -Be 1
        $data[0].ComputerName | Should -Be 'SRV-DEMO-01'
        $data[0].Results.Count | Should -Be 2
    }

    It 'writes one CSV row per check result' {
        $path = Join-Path -Path $TestDrive -ChildPath 'report.csv'
        $script:Report | Export-InfraPulseReport -Path $path -Force
        $rows = @(Import-Csv -LiteralPath $path)

        $rows.Count | Should -Be 2
        $rows[0].ComputerName | Should -Be 'SRV-DEMO-01'
        @($rows.CheckName) | Should -Contain 'Disk'
    }

    It 'serializes timestamps as round-trip ISO 8601 UTC strings in every export format' {
        $jsonPath = Join-Path -Path $TestDrive -ChildPath 'timestamps.json'
        $csvPath = Join-Path -Path $TestDrive -ChildPath 'timestamps.csv'
        $htmlPath = Join-Path -Path $TestDrive -ChildPath 'timestamps.html'
        $script:Report | Export-InfraPulseReport -Path $jsonPath -Force
        $script:Report | Export-InfraPulseReport -Path $csvPath -Force
        $script:Report | Export-InfraPulseReport -Path $htmlPath -Force

        $json = Get-Content -LiteralPath $jsonPath -Raw
        $csv = Get-Content -LiteralPath $csvPath -Raw
        $html = Get-Content -LiteralPath $htmlPath -Raw

        foreach ($content in @($json, $csv, $html)) {
            $content | Should -Not -Match '/Date\('
        }

        $isoPattern = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z'
        $json | Should -Match ('"GeneratedAtUtc":\s*"' + $isoPattern + '"')
        $json | Should -Match ('"TimestampUtc":\s*"' + $isoPattern + '"')
        $json | Should -Match ('"CollectedAtUtc":\s*"' + $isoPattern + '"')
        $json | Should -Match '"LastBootTime":\s*"2026-07-01T06:15:30\.0000000Z"'

        $rows = @(Import-Csv -LiteralPath $csvPath)
        $rows[0].GeneratedAtUtc | Should -Match ('^' + $isoPattern + '$')
        $memoryRow = @($rows | Where-Object { $_.CheckName -eq 'Memory' })[0]
        $memoryRow.EvidenceJson | Should -Match '"LastBootTime":"2026-07-01T06:15:30\.0000000Z"'

        $html | Should -Match '2026-07-01T06:15:30\.0000000Z'
    }

    It 'refuses to overwrite output unless Force is supplied' {
        $path = Join-Path -Path $TestDrive -ChildPath 'existing.html'
        Set-Content -LiteralPath $path -Value 'existing'

        { $script:Report | Export-InfraPulseReport -Path $path } | Should -Throw '*Use -Force*'
    }

    It 'rejects objects that are not InfraPulse reports' {
        { [pscustomobject]@{ Name = 'not-a-report' } | Export-InfraPulseReport -Path (Join-Path $TestDrive 'invalid.html') } | Should -Throw '*not an InfraPulse report*'
    }
}
