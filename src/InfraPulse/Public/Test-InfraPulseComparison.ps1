function Test-InfraPulseComparison {
    <#
    .SYNOPSIS
        Evaluates InfraPulse comparisons against a change policy.

    .DESCRIPTION
        Applies blocking change types to one or more InfraPulse.Comparison objects produced by Compare-InfraPulseReport and returns an InfraPulse.ComparisonEvaluation object describing the outcome. By default NewFinding and Regressed changes block, which turns a pre-change/post-change comparison into a deterministic release gate.

        The command never exits the PowerShell host process. It throws only when ThrowOnFailure is explicitly requested and the evaluation fails.

    .PARAMETER InputObject
        One or more InfraPulse.Comparison objects.

    .PARAMETER FailOn
        Change types that block the evaluation. Defaults to NewFinding and Regressed.

    .PARAMETER Quiet
        Returns only a Boolean evaluation result.

    .PARAMETER ThrowOnFailure
        Throws a terminating error with the evaluation message when blocking changes are present.

    .EXAMPLE
        Compare-InfraPulseReport $before $after | Test-InfraPulseComparison

    .EXAMPLE
        $comparison | Test-InfraPulseComparison -FailOn NewFinding, Regressed, NotComparable -ThrowOnFailure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$InputObject,

        [ValidateSet('NewFinding', 'Regressed', 'Resolved', 'Improved', 'Changed', 'NotComparable', 'Added', 'Unchanged')]
        [string[]]$FailOn = @('NewFinding', 'Regressed'),

        [switch]$Quiet,

        [switch]$ThrowOnFailure
    )

    begin {
        $comparisons = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -eq $InputObject.PSObject.Properties['Changes'] -or $null -eq $InputObject.PSObject.Properties['HasRegressions']) {
            throw 'InputObject is not an InfraPulse comparison.'
        }
        [void]$comparisons.Add($InputObject)
    }

    end {
        if ($comparisons.Count -eq 0) {
            throw 'No InfraPulse comparisons were supplied.'
        }

        $comparisonArray = @($comparisons.ToArray())
        $failOnTypes = @($FailOn | Select-Object -Unique)
        $allChanges = @($comparisonArray | ForEach-Object { @($_.Changes) })
        $violations = @($allChanges | Where-Object { [string]$_.ChangeType -in $failOnTypes })
        $passed = $violations.Count -eq 0

        $message = if ($passed) {
            "$($allChanges.Count) classified change(s) contain no blocking change types ($($failOnTypes -join ', '))."
        }
        else {
            $violationTypes = @($violations | ForEach-Object { [string]$_.ChangeType } | Select-Object -Unique | Sort-Object) -join ', '
            "Comparison evaluation failed: $($violations.Count) blocking change(s) of type $violationTypes."
        }

        $evaluation = [pscustomobject][ordered]@{
            Passed         = $passed
            Message        = $message
            FailOn         = $failOnTypes
            TotalChanges   = $allChanges.Count
            ViolationCount = $violations.Count
            Violations     = @(
                foreach ($violation in $violations) {
                    [pscustomobject][ordered]@{
                        ComputerName     = [string]$violation.ComputerName
                        ChangeType       = [string]$violation.ChangeType
                        CheckName        = [string]$violation.CheckName
                        Target           = [string]$violation.Target
                        ReferenceStatus  = [string]$violation.ReferenceStatus
                        DifferenceStatus = [string]$violation.DifferenceStatus
                    }
                }
            )
            ComputerNames  = @($comparisonArray | ForEach-Object { [string]$_.ComputerName } | Select-Object -Unique)
            GeneratedAtUtc = [DateTime]::UtcNow
        }
        $evaluation.PSObject.TypeNames.Insert(0, 'InfraPulse.ComparisonEvaluation')

        if (-not $passed -and $ThrowOnFailure) {
            throw $message
        }

        if ($Quiet) {
            return $passed
        }

        return $evaluation
    }
}
