function New-InfraPulseComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [AllowNull()]
        [psobject]$ReferenceReport,

        [AllowNull()]
        [psobject]$DifferenceReport,

        [switch]$ExcludeUnchanged
    )

    $changes = New-Object System.Collections.Generic.List[object]

    $referenceResults = if ($null -ne $ReferenceReport) { @($ReferenceReport.Results) } else { @() }
    $differenceResults = if ($null -ne $DifferenceReport) { @($DifferenceReport.Results) } else { @() }

    $differencePool = New-Object System.Collections.Generic.List[object]
    foreach ($result in $differenceResults) {
        [void]$differencePool.Add($result)
    }

    foreach ($referenceResult in $referenceResults) {
        $match = $null
        foreach ($candidate in $differencePool) {
            if (
                [string]$candidate.CheckName -eq [string]$referenceResult.CheckName -and
                [string]$candidate.Target -eq [string]$referenceResult.Target
            ) {
                $match = $candidate
                break
            }
        }

        if ($null -eq $match) {
            [void]$changes.Add((New-InfraPulseResultChange -ChangeType 'NotComparable' -ComputerName $ComputerName -ReferenceResult $referenceResult -DifferenceResult $null))
            continue
        }

        [void]$differencePool.Remove($match)
        [void]$changes.Add((New-InfraPulseResultChange -ChangeType (Get-InfraPulseChangeType -ReferenceResult $referenceResult -DifferenceResult $match) -ComputerName $ComputerName -ReferenceResult $referenceResult -DifferenceResult $match))
    }

    foreach ($differenceResult in $differencePool) {
        $changeType = if ([string]$differenceResult.Status -in @('Warning', 'Critical', 'Unknown')) { 'NewFinding' } else { 'Added' }
        [void]$changes.Add((New-InfraPulseResultChange -ChangeType $changeType -ComputerName $ComputerName -ReferenceResult $null -DifferenceResult $differenceResult))
    }

    $allChanges = @($changes.ToArray())
    $counts = [ordered]@{
        Total         = $allChanges.Count
        NewFinding    = 0
        Regressed     = 0
        Resolved      = 0
        Improved      = 0
        Changed       = 0
        NotComparable = 0
        Added         = 0
        Unchanged     = 0
    }
    foreach ($change in $allChanges) {
        $counts[[string]$change.ChangeType] = [int]$counts[[string]$change.ChangeType] + 1
    }

    $visibleChanges = if ($ExcludeUnchanged) {
        @($allChanges | Where-Object { $_.ChangeType -ne 'Unchanged' })
    }
    else {
        $allChanges
    }

    $referenceMetadata = ConvertTo-InfraPulseComparisonSide -Report $ReferenceReport
    $differenceMetadata = ConvertTo-InfraPulseComparisonSide -Report $DifferenceReport

    $configurationMatches = $null
    if (
        $null -ne $ReferenceReport -and $null -ne $DifferenceReport -and
        -not [string]::IsNullOrWhiteSpace([string]$referenceMetadata.ConfigurationFingerprint) -and
        -not [string]::IsNullOrWhiteSpace([string]$differenceMetadata.ConfigurationFingerprint)
    ) {
        $configurationMatches = [string]$referenceMetadata.ConfigurationFingerprint -eq [string]$differenceMetadata.ConfigurationFingerprint
    }

    $comparison = [pscustomobject][ordered]@{
        SchemaVersion        = '1.1'
        Tool                 = 'InfraPulse'
        ToolVersion          = $script:InfraPulseModuleVersion
        ComputerName         = $ComputerName
        GeneratedAtUtc       = [DateTime]::UtcNow
        Comparable           = ($null -ne $ReferenceReport -and $null -ne $DifferenceReport)
        ConfigurationMatches = $configurationMatches
        HasRegressions       = ([int]$counts.NewFinding + [int]$counts.Regressed) -gt 0
        Reference            = $referenceMetadata
        Difference           = $differenceMetadata
        Summary              = [pscustomobject]$counts
        Changes              = $visibleChanges
    }
    $comparison.PSObject.TypeNames.Insert(0, 'InfraPulse.Comparison')
    return $comparison
}

function ConvertTo-InfraPulseComparisonSide {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$Report
    )

    if ($null -eq $Report) {
        return $null
    }

    $metadata = [ordered]@{
        RunId                    = ''
        GeneratedAtUtc           = $null
        OverallStatus            = [string]$Report.OverallStatus
        ConfigurationFingerprint = ''
    }
    if ($null -ne $Report.PSObject.Properties['RunId']) {
        $metadata.RunId = [string]$Report.RunId
    }
    if ($null -ne $Report.PSObject.Properties['GeneratedAtUtc']) {
        $metadata.GeneratedAtUtc = $Report.GeneratedAtUtc
    }
    if ($null -ne $Report.PSObject.Properties['ConfigurationFingerprint']) {
        $metadata.ConfigurationFingerprint = [string]$Report.ConfigurationFingerprint
    }

    return [pscustomobject]$metadata
}

function Get-InfraPulseStatusSeverity {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Status
    )

    switch ($Status) {
        'Critical' { return 4 }
        'Warning' { return 3 }
        'Unknown' { return 2 }
        'Healthy' { return 1 }
        'Skipped' { return 0 }
        default { return 2 }
    }
}

function Get-InfraPulseChangeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$ReferenceResult,

        [Parameter(Mandatory)]
        [psobject]$DifferenceResult
    )

    $referenceStatus = [string]$ReferenceResult.Status
    $differenceStatus = [string]$DifferenceResult.Status

    if ($referenceStatus -eq $differenceStatus) {
        if (Test-InfraPulseResultChanged -ReferenceResult $ReferenceResult -DifferenceResult $DifferenceResult) {
            return 'Changed'
        }
        return 'Unchanged'
    }

    $referenceSeverity = Get-InfraPulseStatusSeverity -Status $referenceStatus
    $differenceSeverity = Get-InfraPulseStatusSeverity -Status $differenceStatus

    if ($differenceSeverity -gt $referenceSeverity) {
        return 'Regressed'
    }

    if ($differenceStatus -eq 'Healthy' -and $referenceStatus -in @('Warning', 'Critical', 'Unknown')) {
        return 'Resolved'
    }

    return 'Improved'
}

function Test-InfraPulseResultChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$ReferenceResult,

        [Parameter(Mandatory)]
        [psobject]$DifferenceResult
    )

    if ([string]$ReferenceResult.ObservedValue -ne [string]$DifferenceResult.ObservedValue) {
        return $true
    }

    $referenceEvidence = ConvertTo-InfraPulseComparableEvidence -Evidence $ReferenceResult.Evidence
    $differenceEvidence = ConvertTo-InfraPulseComparableEvidence -Evidence $DifferenceResult.Evidence
    return $referenceEvidence -cne $differenceEvidence
}

function ConvertTo-InfraPulseComparableEvidence {
    # Timing values and event samples differ between otherwise identical runs,
    # so they are excluded before evidence is compared.
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Evidence
    )

    if ($null -eq $Evidence) {
        return ''
    }

    $volatileKeys = @('DurationMs', 'TimeoutMs', 'HandshakeMs', 'Samples', 'CollectedAtUtc', 'QueryError')
    $normalized = ConvertTo-InfraPulseSerializableValue -Value $Evidence

    if ($normalized -is [System.Collections.IDictionary]) {
        foreach ($volatileKey in $volatileKeys) {
            if ($normalized.Contains($volatileKey)) {
                $normalized.Remove($volatileKey)
            }
        }
    }
    elseif ($normalized -is [System.Management.Automation.PSCustomObject]) {
        foreach ($volatileKey in $volatileKeys) {
            $property = $normalized.PSObject.Properties[$volatileKey]
            if ($null -ne $property) {
                $normalized.PSObject.Properties.Remove($volatileKey)
            }
        }
    }

    return ConvertTo-Json -InputObject $normalized -Depth 8 -Compress
}

function New-InfraPulseResultChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('NewFinding', 'Regressed', 'Resolved', 'Improved', 'Changed', 'NotComparable', 'Added', 'Unchanged')]
        [string]$ChangeType,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [AllowNull()]
        [psobject]$ReferenceResult,

        [AllowNull()]
        [psobject]$DifferenceResult
    )

    $template = if ($null -ne $DifferenceResult) { $DifferenceResult } else { $ReferenceResult }
    $change = [pscustomobject][ordered]@{
        ChangeType              = $ChangeType
        ComputerName            = $ComputerName
        CheckName               = [string]$template.CheckName
        Category                = [string]$template.Category
        Target                  = [string]$template.Target
        ReferenceStatus         = if ($null -ne $ReferenceResult) { [string]$ReferenceResult.Status } else { $null }
        DifferenceStatus        = if ($null -ne $DifferenceResult) { [string]$DifferenceResult.Status } else { $null }
        ReferenceObservedValue  = if ($null -ne $ReferenceResult) { $ReferenceResult.ObservedValue } else { $null }
        DifferenceObservedValue = if ($null -ne $DifferenceResult) { $DifferenceResult.ObservedValue } else { $null }
        ReferenceMessage        = if ($null -ne $ReferenceResult) { [string]$ReferenceResult.Message } else { $null }
        DifferenceMessage       = if ($null -ne $DifferenceResult) { [string]$DifferenceResult.Message } else { $null }
        EvidenceChanged         = if ($null -ne $ReferenceResult -and $null -ne $DifferenceResult) { Test-InfraPulseResultChanged -ReferenceResult $ReferenceResult -DifferenceResult $DifferenceResult } else { $null }
    }
    $change.PSObject.TypeNames.Insert(0, 'InfraPulse.ResultChange')
    return $change
}
