@{
    RootModule           = 'InfraPulse.psm1'
    ModuleVersion        = '1.2.0'
    GUID                 = '381fa9f8-98e3-43b2-893d-909bbfc10378'
    Author               = 'Flurin Gubler'
    CompanyName          = 'xGreeny'
    Copyright            = '(c) 2026 Flurin Gubler. Released under the MIT License.'
    Description          = 'Read-only infrastructure health checks and self-contained reports for Windows and hybrid environments.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Compare-InfraPulseReport'
        'Export-InfraPulseComparison'
        'Export-InfraPulseReport'
        'Get-InfraPulseCheck'
        'Import-InfraPulseReport'
        'Invoke-InfraPulse'
        'New-InfraPulseConfiguration'
        'Test-InfraPulseConfiguration'
        'Test-InfraPulseReport'
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
            ReleaseNotes = 'Recognizes auto-rotating short-lived certificates by construction: healthy and visible while valid, critical only when the rotation breaks. Configurable through Checks.Certificates.TreatShortLivedAsRotating.'
        }
    }
}
