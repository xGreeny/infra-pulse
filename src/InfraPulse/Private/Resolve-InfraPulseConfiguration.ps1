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

    if ($ConfigurationPath) {
        $resolvedPath = (Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Stop).ProviderPath
        if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
            throw "Configuration files must use the .psd1 extension: '$resolvedPath'."
        }
        $override = Import-PowerShellDataFile -Path $resolvedPath
    }
    elseif ($null -ne $Configuration) {
        $override = $Configuration
    }

    $merged = Merge-InfraPulseHashtable -Base (Get-DefaultInfraPulseConfiguration) -Override $override
    $validation = Test-InfraPulseConfigurationData -Configuration $merged

    if (-not $validation.IsValid) {
        $message = 'InfraPulse configuration is invalid:' + [Environment]::NewLine + (($validation.Errors | ForEach-Object { " - $_" }) -join [Environment]::NewLine)
        throw $message
    }

    return $merged
}
