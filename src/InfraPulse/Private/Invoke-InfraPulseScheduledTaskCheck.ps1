function Invoke-InfraPulseScheduledTaskCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        param($CheckSettings)

        if ($env:OS -ne 'Windows_NT') {
            throw 'The ScheduledTasks check requires a Windows target.'
        }

        if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{
                Supported      = $false
                EvaluatedCount = 0
                FailedTasks    = @()
            }
        }

        $failedTasks = New-Object System.Collections.Generic.List[object]
        $evaluatedCount = 0

        foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
            if ([string]$task.State -eq 'Disabled') {
                continue
            }

            $taskPath = [string]$task.TaskPath
            $taskName = [string]$task.TaskName

            $included = $false
            foreach ($pattern in @($CheckSettings.IncludePaths)) {
                if ($taskPath -like [string]$pattern) {
                    $included = $true
                    break
                }
            }
            if (-not $included) {
                continue
            }

            $excluded = $false
            foreach ($pattern in @($CheckSettings.ExcludePaths)) {
                if ($taskPath -like [string]$pattern) {
                    $excluded = $true
                    break
                }
            }
            if (-not $excluded) {
                foreach ($pattern in @($CheckSettings.ExcludeTasks)) {
                    if ($taskName -like [string]$pattern) {
                        $excluded = $true
                        break
                    }
                }
            }
            if ($excluded) {
                continue
            }

            $evaluatedCount++

            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
            }
            catch {
                continue
            }

            $lastResult = [int64]$taskInfo.LastTaskResult
            if ($lastResult -eq 0 -or $lastResult -in @($CheckSettings.ExcludeResults | ForEach-Object { [int64]$_ })) {
                continue
            }

            $failedTaskRecord = [pscustomobject]@{
                TaskPath       = $taskPath
                TaskName       = $taskName
                LastTaskResult = $lastResult
                LastRunTime    = $taskInfo.LastRunTime
            }
            [void]$failedTasks.Add($failedTaskRecord)
        }

        [pscustomobject]@{
            Supported      = $true
            EvaluatedCount = $evaluatedCount
            FailedTasks    = @($failedTasks.ToArray())
        }
    }

    $taskState = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings)
    $stopwatch.Stop()

    if (-not [bool]$taskState.Supported) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'ScheduledTasks' -Category 'Availability' -ComputerName $Context.ComputerName -Target 'Scheduled tasks' -Message 'Scheduled-task interfaces are unavailable on the target.' -Recommendation 'Get-ScheduledTask requires the ScheduledTasks module (Windows Server 2012 / Windows 8 or later).' -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $failedTasks = @($taskState.FailedTasks)
    $failedCount = $failedTasks.Count
    $evaluatedCount = [int]$taskState.EvaluatedCount

    if ($failedCount -ge [int]$Settings.CriticalCount) {
        $status = 'Critical'
        $message = "$failedCount of $evaluatedCount evaluated scheduled task(s) failed their last run."
        $recommendation = 'Review the failing tasks; silently failing maintenance and backup jobs are a common root cause of later data loss.'
    }
    elseif ($failedCount -ge [int]$Settings.WarningCount) {
        $status = 'Warning'
        $message = "$failedCount of $evaluatedCount evaluated scheduled task(s) failed their last run."
        $recommendation = 'Check the task result codes and last run times, then re-run or repair the failing tasks.'
    }
    else {
        $status = 'Healthy'
        $message = "All $evaluatedCount evaluated scheduled task(s) completed their last run successfully."
        $recommendation = ''
    }

    $evidence = [ordered]@{
        FailedCount    = $failedCount
        EvaluatedCount = $evaluatedCount
        FailedTasks    = @(
            $failedTasks |
                Select-Object -First 25 |
                ForEach-Object {
                    [pscustomobject]@{
                        Task           = ('{0}{1}' -f $_.TaskPath, $_.TaskName)
                        LastTaskResult = ('0x{0:X}' -f [int64]$_.LastTaskResult)
                        LastRunTime    = $_.LastRunTime
                    }
                }
        )
        Truncated      = $failedCount -gt 25
    }

    return New-InfraPulseResult -Status $status -CheckName 'ScheduledTasks' -Category 'Availability' -ComputerName $Context.ComputerName -Target 'Scheduled tasks' -Message $message -ObservedValue $failedCount -WarningThreshold (">= {0} failed task(s)" -f $Settings.WarningCount) -CriticalThreshold (">= {0} failed task(s)" -f $Settings.CriticalCount) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
