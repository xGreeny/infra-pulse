function Get-InfraPulseSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $counts = [ordered]@{
        Total    = @($Results).Count
        Healthy  = @($Results | Where-Object { $_.Status -eq 'Healthy' }).Count
        Warning  = @($Results | Where-Object { $_.Status -eq 'Warning' }).Count
        Critical = @($Results | Where-Object { $_.Status -eq 'Critical' }).Count
        Unknown  = @($Results | Where-Object { $_.Status -eq 'Unknown' }).Count
        Skipped  = @($Results | Where-Object { $_.Status -eq 'Skipped' }).Count
    }

    if ($counts.Critical -gt 0) {
        $overallStatus = 'Critical'
    }
    elseif ($counts.Warning -gt 0) {
        $overallStatus = 'Warning'
    }
    elseif ($counts.Unknown -gt 0) {
        $overallStatus = 'Unknown'
    }
    elseif ($counts.Healthy -gt 0) {
        $overallStatus = 'Healthy'
    }
    else {
        $overallStatus = 'Skipped'
    }

    [pscustomobject]@{
        OverallStatus = $overallStatus
        Counts        = [pscustomobject]$counts
    }
}
