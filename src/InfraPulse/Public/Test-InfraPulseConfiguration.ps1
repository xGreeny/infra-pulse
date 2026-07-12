function Test-InfraPulseConfiguration {
    <#
    .SYNOPSIS
        Validates an InfraPulse configuration.

    .DESCRIPTION
        Loads a partial or complete configuration, merges it with the module defaults, and validates the effective configuration without running any checks.

    .PARAMETER Path
        Path to a PowerShell data file (.psd1).

    .PARAMETER Configuration
        Configuration hashtable supplied directly.

    .PARAMETER Quiet
        Returns only a Boolean validation result.

    .EXAMPLE
        Test-InfraPulseConfiguration -Path .\config\infra-pulse.example.psd1

    .EXAMPLE
        Test-InfraPulseConfiguration -Configuration @{ Checks = @{ Uptime = @{ WarningDays = 30 } } }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Configuration')]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Configuration,

        [switch]$Quiet
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
            if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
                throw 'Configuration files must use the .psd1 extension.'
            }
            $inputConfiguration = Import-PowerShellDataFile -Path $resolvedPath
            $source = $resolvedPath
        }
        else {
            $inputConfiguration = $Configuration
            $source = 'In-memory configuration'
        }

        $effective = Merge-InfraPulseHashtable -Base (Get-DefaultInfraPulseConfiguration) -Override $inputConfiguration
        $validation = Test-InfraPulseConfigurationData -Configuration $effective
        $result = [pscustomobject]@{
            Source                 = $source
            IsValid                = [bool]$validation.IsValid
            Errors                 = @($validation.Errors)
            Warnings               = @($validation.Warnings)
            EffectiveConfiguration = $effective
        }
    }
    catch {
        $result = [pscustomobject]@{
            Source                 = if ($PSCmdlet.ParameterSetName -eq 'Path') { $Path } else { 'In-memory configuration' }
            IsValid                = $false
            Errors                 = @($_.Exception.Message)
            Warnings               = @()
            EffectiveConfiguration = $null
        }
    }

    if ($Quiet) {
        return [bool]$result.IsValid
    }

    return $result
}
