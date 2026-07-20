function Test-InfraPulseReport {
    <#
    .SYNOPSIS
        Evaluates InfraPulse reports against a release or change policy.

    .DESCRIPTION
        Applies blocking statuses, a warning budget, and optional wildcard ignore rules to one or more reports and returns an InfraPulse.PolicyEvaluation object describing the outcome. The policy can be supplied inline through FailOn and MaximumWarnings or loaded from a validated PowerShell data file.

        The command never exits the PowerShell host process. It throws only when ThrowOnFailure is explicitly requested and the evaluation fails.

    .PARAMETER InputObject
        One or more InfraPulse.Report objects.

    .PARAMETER FailOn
        Result statuses that block the evaluation. Defaults to Critical and Unknown.

    .PARAMETER MaximumWarnings
        Number of Warning results tolerated after ignore rules are applied. Defaults to 0.

    .PARAMETER PolicyPath
        Path to a policy data file with FailOn, MaximumWarnings, and Ignore rules. Cannot be combined with FailOn or MaximumWarnings.

    .PARAMETER Quiet
        Returns only a Boolean evaluation result.

    .PARAMETER ThrowOnFailure
        Throws a terminating error with the evaluation message when the policy is not satisfied.

    .EXAMPLE
        $evaluation = $report | Test-InfraPulseReport -FailOn Critical, Unknown -MaximumWarnings 0

    .EXAMPLE
        $report | Test-InfraPulseReport -PolicyPath .\config\change-policy.example.psd1 -ThrowOnFailure
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inline')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$InputObject,

        [Parameter(ParameterSetName = 'Inline')]
        [ValidateSet('Healthy', 'Warning', 'Critical', 'Unknown', 'Skipped')]
        [string[]]$FailOn = @('Critical', 'Unknown'),

        [Parameter(ParameterSetName = 'Inline')]
        [ValidateRange(0, 2147483647)]
        [int]$MaximumWarnings = 0,

        [Parameter(Mandatory, ParameterSetName = 'Policy')]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyPath,

        [switch]$Quiet,

        [switch]$ThrowOnFailure
    )

    begin {
        $reports = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -eq $InputObject.PSObject.Properties['Results'] -or $null -eq $InputObject.PSObject.Properties['OverallStatus']) {
            throw 'InputObject is not an InfraPulse report.'
        }
        [void]$reports.Add($InputObject)
    }

    end {
        if ($reports.Count -eq 0) {
            throw 'No InfraPulse reports were supplied.'
        }

        if ($PSCmdlet.ParameterSetName -eq 'Policy') {
            $policy = Import-InfraPulseChangePolicy -Path $PolicyPath
            $policySource = (Resolve-Path -LiteralPath $PolicyPath).ProviderPath
        }
        else {
            $policy = [pscustomobject]@{
                FailOn          = @($FailOn | Select-Object -Unique)
                MaximumWarnings = $MaximumWarnings
                Ignore          = @()
            }
            $policySource = 'Inline parameters'
        }

        $allResults = @($reports | ForEach-Object { @($_.Results) })
        $ignoredResults = New-Object System.Collections.Generic.List[object]
        $evaluatedResults = New-Object System.Collections.Generic.List[object]

        foreach ($result in $allResults) {
            if (Test-InfraPulseIgnoreRuleMatch -Result $result -Rules $policy.Ignore) {
                [void]$ignoredResults.Add($result)
            }
            else {
                [void]$evaluatedResults.Add($result)
            }
        }

        $blocking = @($evaluatedResults | Where-Object { [string]$_.Status -in @($policy.FailOn) })
        $warningCount = @($evaluatedResults | Where-Object { [string]$_.Status -eq 'Warning' -and 'Warning' -notin @($policy.FailOn) }).Count
        $warningsExceeded = $warningCount -gt [int]$policy.MaximumWarnings
        $passed = ($blocking.Count -eq 0) -and (-not $warningsExceeded)

        $messageParts = @()
        if ($blocking.Count -gt 0) {
            $blockingStatuses = @($blocking | ForEach-Object { [string]$_.Status } | Select-Object -Unique | Sort-Object) -join ', '
            $messageParts += "$($blocking.Count) blocking result(s) with status $blockingStatuses"
        }
        if ($warningsExceeded) {
            $messageParts += "$warningCount warning(s) exceed the budget of $($policy.MaximumWarnings)"
        }
        $message = if ($passed) {
            "$($evaluatedResults.Count) evaluated result(s) satisfy the policy; $($ignoredResults.Count) result(s) were ignored."
        }
        else {
            'Policy evaluation failed: ' + ($messageParts -join ' and ') + "; $($ignoredResults.Count) result(s) were ignored."
        }

        $evaluation = [pscustomobject][ordered]@{
            Passed          = $passed
            Message         = $message
            PolicySource    = $policySource
            FailOn          = @($policy.FailOn)
            MaximumWarnings = [int]$policy.MaximumWarnings
            TotalResults    = $allResults.Count
            EvaluatedCount  = $evaluatedResults.Count
            IgnoredCount    = $ignoredResults.Count
            BlockingCount   = $blocking.Count
            WarningCount    = $warningCount
            Blocking        = @(
                foreach ($result in $blocking) {
                    [pscustomobject][ordered]@{
                        ComputerName = [string]$result.ComputerName
                        CheckName    = [string]$result.CheckName
                        Target       = [string]$result.Target
                        Status       = [string]$result.Status
                        Message      = [string]$result.Message
                    }
                }
            )
            ComputerNames   = @($reports | ForEach-Object { [string]$_.ComputerName } | Select-Object -Unique)
            GeneratedAtUtc  = [DateTime]::UtcNow
        }
        $evaluation.PSObject.TypeNames.Insert(0, 'InfraPulse.PolicyEvaluation')

        if (-not $passed -and $ThrowOnFailure) {
            throw $message
        }

        if ($Quiet) {
            return $passed
        }

        return $evaluation
    }
}
