function Resolve-InfraPulseConfiguration {
    [CmdletBinding()]
    param(
        [string]$ConfigurationPath,

        [System.Collections.IDictionary]$Configuration
    )

    if ($ConfigurationPath -and $null -ne $Configuration) {
        throw 'Specify either ConfigurationPath or Configuration, not both.'
    }

    $override = @{}
    $source = 'Built-in defaults'

    if ($ConfigurationPath) {
        $resolvedPath = Resolve-InfraPulseConfigurationFile -Path $ConfigurationPath
        $override = Import-PowerShellDataFile -Path $resolvedPath
        $source = "Parameter: $resolvedPath"
    }
    elseif ($null -ne $Configuration) {
        $override = $Configuration
        $source = 'Inline configuration'
    }
    else {
        # Discovery keeps unattended runs on the intended configuration: an
        # explicitly set INFRAPULSE_CONFIG wins and must exist; otherwise an
        # infra-pulse.psd1 in the working directory is picked up.
        $environmentPath = $env:INFRAPULSE_CONFIG
        if (-not [string]::IsNullOrWhiteSpace($environmentPath)) {
            if (-not (Test-Path -LiteralPath $environmentPath)) {
                throw "INFRAPULSE_CONFIG points to '$environmentPath', which does not exist."
            }
            $resolvedPath = Resolve-InfraPulseConfigurationFile -Path $environmentPath
            $override = Import-PowerShellDataFile -Path $resolvedPath
            $source = "INFRAPULSE_CONFIG: $resolvedPath"
        }
        else {
            $workingDirectoryPath = Join-Path -Path (Get-Location).Path -ChildPath 'infra-pulse.psd1'
            if (Test-Path -LiteralPath $workingDirectoryPath) {
                $resolvedPath = Resolve-InfraPulseConfigurationFile -Path $workingDirectoryPath
                $override = Import-PowerShellDataFile -Path $resolvedPath
                $source = "Working directory: $resolvedPath"
            }
        }
    }

    $merged = Merge-InfraPulseHashtable -Base (Get-DefaultInfraPulseConfiguration) -Override $override
    $validation = Test-InfraPulseConfigurationData -Configuration $merged

    if (-not $validation.IsValid) {
        $message = 'InfraPulse configuration is invalid:' + [Environment]::NewLine + (($validation.Errors | ForEach-Object { " - $_" }) -join [Environment]::NewLine)
        throw $message
    }

    [pscustomobject]@{
        Configuration = $merged
        Source        = $source
    }
}

function Resolve-InfraPulseConfigurationFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
        throw "Configuration files must use the .psd1 extension: '$resolvedPath'."
    }
    return $resolvedPath
}
