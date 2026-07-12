function Get-InfraPulseCheck {
    <#
    .SYNOPSIS
        Lists built-in InfraPulse checks.

    .DESCRIPTION
        Returns the check catalog, including category, platform requirement, default enabled state, and purpose.

    .PARAMETER Name
        Limits output to one or more check names. Wildcards are supported.

    .EXAMPLE
        Get-InfraPulseCheck

    .EXAMPLE
        Get-InfraPulseCheck -Name '*Sync', 'Disk'
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name = @('*')
    )

    $configuration = Get-DefaultInfraPulseConfiguration
    foreach ($check in Get-InfraPulseCheckCatalog) {
        $matched = $false
        foreach ($pattern in $Name) {
            if ($check.Name -like $pattern) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            continue
        }

        [pscustomobject]@{
            Name            = $check.Name
            Category        = $check.Category
            EnabledByDefault = [bool]$configuration.Checks[$check.Name].Enabled
            RequiresWindows = [bool]$check.RequiresWindows
            Description     = $check.Description
        }
    }
}
