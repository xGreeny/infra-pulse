function Get-InfraPulseStatusCssClass {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Status
    )

    switch ($Status) {
        'Healthy' { return 'healthy' }
        'Warning' { return 'warning' }
        'Critical' { return 'critical' }
        'Unknown' { return 'unknown' }
        'Skipped' { return 'skipped' }
        default { return 'unknown' }
    }
}
