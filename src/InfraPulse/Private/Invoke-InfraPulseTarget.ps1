function Invoke-InfraPulseTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Configuration,

        [Parameter(Mandatory)]
        [string[]]$Checks,

        [switch]$FailFast,

        [string[]]$Tags = @(),

        [string]$RunId = '',

        [string]$ConfigurationFingerprint = '',

        [string]$ConfigurationSource = '',

        [string]$EnvironmentName = ''
    )

    $startedAtUtc = [DateTime]::UtcNow
    $targetStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = @()
    $inventory = $null
    $reportedInventory = $null

    try {
        $inventory = Get-InfraPulseInventory -Context $Context
        if ($null -ne $inventory -and -not [string]::IsNullOrWhiteSpace([string]$inventory.ComputerName)) {
            $Context.ComputerName = [string]$inventory.ComputerName
        }
        if ([bool]$Configuration.General.IncludeInventory) {
            $reportedInventory = $inventory
        }
    }
    catch {
        $results += New-InfraPulseResult -Status 'Unknown' -CheckName 'Inventory' -Category 'Control' -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message 'Host inventory could not be collected.' -Recommendation 'Validate the target platform, remoting endpoint, and access to Windows CIM classes.' -Evidence ([ordered]@{ Error = $_.Exception.Message }) -ErrorMessage $_.Exception.Message
        if ($FailFast -or -not [bool]$Configuration.General.ContinueOnError) {
            throw
        }
    }

    $catalog = @(Get-InfraPulseCheckCatalog)
    foreach ($checkName in $Checks) {
        $checkDefinition = $catalog | Where-Object { $_.Name -eq $checkName } | Select-Object -First 1
        if ($null -eq $checkDefinition) {
            $results += New-InfraPulseResult -Status 'Unknown' -CheckName $checkName -Category 'Control' -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message "Check '$checkName' is not registered." -Recommendation 'Use Get-InfraPulseCheck to list available checks.'
            continue
        }

        if (
            $null -ne $inventory -and
            [bool]$checkDefinition.RequiresWindows -and
            [string]$inventory.Platform -ne 'Windows'
        ) {
            $results += New-InfraPulseResult -Status 'Skipped' -CheckName $checkDefinition.Name -Category $checkDefinition.Category -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message "The $($checkDefinition.Name) check requires a Windows target." -Recommendation 'Run this check against a Windows host or select cross-platform connectivity checks.'
            continue
        }

        try {
            Write-Verbose "[$($Context.ComputerName)] Running $checkName check."
            $functionName = [string]$checkDefinition.FunctionName
            $checkResults = @(& $functionName -Context $Context -Settings $Configuration.Checks[$checkName])
            if ($checkResults.Count -eq 0) {
                $results += New-InfraPulseResult -Status 'Unknown' -CheckName $checkName -Category $checkDefinition.Category -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message "Check '$checkName' returned no result." -Recommendation 'Review the check configuration and run with -Verbose for additional context.'
            }
            else {
                $results += $checkResults
            }
        }
        catch {
            $results += New-InfraPulseResult -Status 'Unknown' -CheckName $checkName -Category $checkDefinition.Category -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message "Check '$checkName' could not be completed." -Recommendation 'Review the captured error, target prerequisites, and account permissions.' -Evidence ([ordered]@{ Error = $_.Exception.Message }) -ErrorMessage $_.Exception.Message
            if ($FailFast -or -not [bool]$Configuration.General.ContinueOnError) {
                throw
            }
        }
    }

    if ($Checks.Count -eq 0) {
        $results += New-InfraPulseResult -Status 'Skipped' -CheckName 'Configuration' -Category 'Control' -ComputerName $Context.ComputerName -Target $Context.ComputerName -Message 'No checks are enabled or selected.' -Recommendation 'Enable checks in the configuration or provide -Check explicitly.'
    }

    $targetStopwatch.Stop()
    return New-InfraPulseReport -RequestedComputerName $Context.RequestedComputerName -ComputerName $Context.ComputerName -Inventory $reportedInventory -Results $results -DurationMs $targetStopwatch.Elapsed.TotalMilliseconds -Tags $Tags -RunId $RunId -StartedAtUtc $startedAtUtc -ConfigurationFingerprint $ConfigurationFingerprint -ConfigurationSource $ConfigurationSource -EnvironmentName $EnvironmentName
}
