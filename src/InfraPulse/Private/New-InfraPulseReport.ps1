function New-InfraPulseReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RequestedComputerName,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [AllowNull()]
        [psobject]$Inventory,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results,

        [double]$DurationMs,

        [string[]]$Tags = @()
    )

    $summary = Get-InfraPulseSummary -Results $Results
    $report = [pscustomobject][ordered]@{
        SchemaVersion         = '1.0'
        Tool                  = 'InfraPulse'
        ToolVersion           = $script:InfraPulseModuleVersion
        RequestedComputerName = $RequestedComputerName
        ComputerName          = $ComputerName
        GeneratedAtUtc        = [DateTime]::UtcNow
        OverallStatus         = $summary.OverallStatus
        Summary               = $summary.Counts
        Inventory             = $Inventory
        Results               = @($Results)
        Tags                  = @($Tags)
        DurationMs            = [math]::Round($DurationMs, 2, [MidpointRounding]::AwayFromZero)
    }
    $report.PSObject.TypeNames.Insert(0, 'InfraPulse.Report')
    return $report
}
