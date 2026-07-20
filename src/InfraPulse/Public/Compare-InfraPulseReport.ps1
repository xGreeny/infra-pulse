function Compare-InfraPulseReport {
    <#
    .SYNOPSIS
        Compares two InfraPulse report snapshots.

    .DESCRIPTION
        Pairs reference and difference reports by computer name, matches their results by check name and target, and classifies every delta as NewFinding, Regressed, Resolved, Improved, Changed, NotComparable, Added, or Unchanged. The returned InfraPulse.Comparison objects carry per-type counts, run metadata from both snapshots, and a configuration-fingerprint match indicator so pre-change and post-change evidence is only treated as equivalent when it was collected with the same effective configuration.

        Volatile evidence such as timing values and event samples is ignored when deciding whether a result changed.

    .PARAMETER ReferenceObject
        One or more reports that represent the earlier snapshot.

    .PARAMETER DifferenceObject
        One or more reports that represent the later snapshot.

    .PARAMETER ExcludeUnchanged
        Omits Unchanged entries from the Changes collection. Summary counts still include them.

    .EXAMPLE
        $comparison = Compare-InfraPulseReport -ReferenceObject $before -DifferenceObject $after

    .EXAMPLE
        Compare-InfraPulseReport (Import-InfraPulseReport .\before.json) (Import-InfraPulseReport .\after.json) -ExcludeUnchanged
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        [object[]]$ReferenceObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        [object[]]$DifferenceObject,

        [switch]$ExcludeUnchanged
    )

    foreach ($report in @($ReferenceObject) + @($DifferenceObject)) {
        if ($null -eq $report.PSObject.Properties['Results'] -or $null -eq $report.PSObject.Properties['OverallStatus']) {
            throw 'ReferenceObject and DifferenceObject must contain InfraPulse reports.'
        }
    }

    $referenceByComputer = @{}
    foreach ($report in @($ReferenceObject)) {
        $referenceByComputer[([string]$report.ComputerName).ToUpperInvariant()] = $report
    }
    $differenceByComputer = @{}
    foreach ($report in @($DifferenceObject)) {
        $differenceByComputer[([string]$report.ComputerName).ToUpperInvariant()] = $report
    }

    $computerNames = New-Object System.Collections.Generic.List[string]
    foreach ($report in @($ReferenceObject)) {
        if ($computerNames -notcontains [string]$report.ComputerName) {
            [void]$computerNames.Add([string]$report.ComputerName)
        }
    }
    foreach ($report in @($DifferenceObject)) {
        $known = @($computerNames | Where-Object { $_.ToUpperInvariant() -eq ([string]$report.ComputerName).ToUpperInvariant() })
        if ($known.Count -eq 0) {
            [void]$computerNames.Add([string]$report.ComputerName)
        }
    }

    foreach ($computerName in $computerNames) {
        $key = $computerName.ToUpperInvariant()
        $referenceReport = if ($referenceByComputer.ContainsKey($key)) { $referenceByComputer[$key] } else { $null }
        $differenceReport = if ($differenceByComputer.ContainsKey($key)) { $differenceByComputer[$key] } else { $null }

        New-InfraPulseComparison -ComputerName $computerName -ReferenceReport $referenceReport -DifferenceReport $differenceReport -ExcludeUnchanged:$ExcludeUnchanged
    }
}
