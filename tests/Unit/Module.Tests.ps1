BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse module surface' {
    It 'has a valid module manifest' {
        $manifest = Test-ModuleManifest -Path $script:ModulePath -ErrorAction Stop
        $manifest.Name | Should -Be 'InfraPulse'
        $manifest.Version.ToString() | Should -Be '1.4.0'
        $manifest.PowerShellVersion.ToString() | Should -Be '5.1'
    }

    It 'exports only the documented public commands' {
        $expected = @(
            'Compare-InfraPulseReport'
            'Export-InfraPulseComparison'
            'Export-InfraPulseReport'
            'Get-InfraPulseCheck'
            'Import-InfraPulseReport'
            'Invoke-InfraPulse'
            'New-InfraPulseConfiguration'
            'Test-InfraPulseComparison'
            'Test-InfraPulseConfiguration'
            'Test-InfraPulseReport'
        ) | Sort-Object
        $actual = Get-Command -Module InfraPulse -CommandType Function |
            Select-Object -ExpandProperty Name |
            Sort-Object

        ($actual -join '|') | Should -Be ($expected -join '|')
    }

    It 'provides complete comment-based help for every public command' {
        foreach ($commandName in Get-Command -Module InfraPulse -CommandType Function | Select-Object -ExpandProperty Name) {
            $help = Get-Help -Name $commandName -Full
            [string]$help.Synopsis | Should -Not -BeNullOrEmpty -Because "$commandName requires a synopsis"
            (@($help.Description.Text) -join ' ') | Should -Not -BeNullOrEmpty -Because "$commandName requires a description"
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 1 -Because "$commandName requires at least one example"
        }
    }

    It 'publishes a unique twelve-check catalog' {
        $checks = @(Get-InfraPulseCheck)
        $checks.Count | Should -Be 12
        @($checks.Name | Select-Object -Unique).Count | Should -Be 12
        @($checks | Where-Object { [string]::IsNullOrWhiteSpace($_.Description) }).Count | Should -Be 0
        @($checks.Name) | Should -Contain 'Tls'
        @($checks.Name) | Should -Contain 'PatchAge'
    }

    It 'supports wildcard catalog filtering' {
        $checks = @(Get-InfraPulseCheck -Name '*Sync', 'Disk')
        ($checks.Name | Sort-Object) -join '|' | Should -Be 'Disk|TimeSync'
    }
}
