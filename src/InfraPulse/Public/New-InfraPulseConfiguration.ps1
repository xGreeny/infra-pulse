function New-InfraPulseConfiguration {
    <#
    .SYNOPSIS
        Creates a documented InfraPulse configuration file.

    .DESCRIPTION
        Writes a ready-to-edit PowerShell data file containing the complete configuration schema or a compact baseline.

    .PARAMETER Path
        Destination path. The file must use the .psd1 extension.

    .PARAMETER Minimal
        Creates a compact override file with the core local checks.

    .PARAMETER Force
        Overwrites an existing file.

    .PARAMETER PassThru
        Returns the created file.

    .EXAMPLE
        New-InfraPulseConfiguration -Path .\infra-pulse.psd1

    .EXAMPLE
        New-InfraPulseConfiguration -Path .\infra-pulse.minimal.psd1 -Minimal -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Minimal,

        [switch]$Force,

        [switch]$PassThru
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
        throw "Configuration path must use the .psd1 extension: '$resolvedPath'."
    }

    if ((Test-Path -LiteralPath $resolvedPath) -and -not $Force) {
        throw "File already exists: '$resolvedPath'. Use -Force to overwrite it."
    }

    $parent = Split-Path -Path $resolvedPath -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -Path $parent -ItemType Directory -Force
    }

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Create InfraPulse configuration')) {
        $content = Get-InfraPulseConfigurationTemplate -Minimal:$Minimal
        Write-InfraPulseUtf8File -Path $resolvedPath -Content $content

        if ($PassThru) {
            return Get-Item -LiteralPath $resolvedPath
        }
    }
}
