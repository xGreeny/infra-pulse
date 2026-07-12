@{
    RootModule           = 'InfraPulse.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '381fa9f8-98e3-43b2-893d-909bbfc10378'
    Author               = 'Flurin Gubler'
    CompanyName          = 'xGreeny'
    Copyright            = '(c) 2026 Flurin Gubler. Released under the MIT License.'
    Description          = 'Read-only infrastructure health checks and self-contained reports for Windows and hybrid environments.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Export-InfraPulseReport'
        'Get-InfraPulseCheck'
        'Invoke-InfraPulse'
        'New-InfraPulseConfiguration'
        'Test-InfraPulseConfiguration'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FormatsToProcess = @('Formats/InfraPulse.Format.ps1xml')

    PrivateData = @{
        PSData = @{
            Tags = @(
                'Windows'
                'Infrastructure'
                'HealthCheck'
                'Monitoring'
                'PowerShell'
                'SystemAdministration'
                'Automation'
                'WinRM'
            )
            LicenseUri = 'https://github.com/xGreeny/infra-pulse/blob/main/LICENSE'
            ProjectUri = 'https://github.com/xGreeny/infra-pulse'
            ReleaseNotes = 'Initial stable release with ten built-in checks, remote execution, configuration validation, and HTML, JSON, and CSV reporting.'
        }
    }
}
