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

        [string[]]$Tags = @(),

        [string]$RunId = '',

        [datetime]$StartedAtUtc,

        [string]$ConfigurationFingerprint = '',

        [string]$ConfigurationSource = ''
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = [guid]::NewGuid().ToString()
    }

    $completedAtUtc = [DateTime]::UtcNow
    if (-not $PSBoundParameters.ContainsKey('StartedAtUtc')) {
        $StartedAtUtc = $completedAtUtc.AddMilliseconds(-$DurationMs)
    }

    $summary = Get-InfraPulseSummary -Results $Results
    $report = [pscustomobject][ordered]@{
        SchemaVersion            = '1.2'
        Tool                     = 'InfraPulse'
        ToolVersion              = $script:InfraPulseModuleVersion
        RunId                    = $RunId
        RequestedComputerName    = $RequestedComputerName
        ComputerName             = $ComputerName
        GeneratedAtUtc           = $completedAtUtc
        StartedAtUtc             = $StartedAtUtc.ToUniversalTime()
        CompletedAtUtc           = $completedAtUtc
        ConfigurationFingerprint = $ConfigurationFingerprint
        ConfigurationSource      = $ConfigurationSource
        OverallStatus            = $summary.OverallStatus
        Summary                  = $summary.Counts
        Inventory                = $Inventory
        Results                  = @($Results)
        Tags                     = @($Tags)
        DurationMs               = [math]::Round($DurationMs, 2, [MidpointRounding]::AwayFromZero)
    }
    $report.PSObject.TypeNames.Insert(0, 'InfraPulse.Report')
    return $report
}
