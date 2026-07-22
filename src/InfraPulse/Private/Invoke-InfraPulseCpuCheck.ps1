function Invoke-InfraPulseCpuCheck {
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
            throw 'The Cpu check requires a Windows target.'
        }

        $useCim = [bool](Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)
        $samples = New-Object System.Collections.Generic.List[double]

        # A single reading is a coin flip on a busy host; a short averaged
        # series separates sustained pressure from momentary spikes.
        for ($sampleIndex = 1; $sampleIndex -le [int]$CheckSettings.SampleCount; $sampleIndex++) {
            $processors = if ($useCim) {
                @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
            }
            else {
                @(Get-WmiObject -Class Win32_Processor -ErrorAction Stop)
            }

            $loadValues = @(
                foreach ($processor in $processors) {
                    $loadProperty = $processor.PSObject.Properties['LoadPercentage']
                    if ($null -ne $loadProperty -and $null -ne $loadProperty.Value) {
                        [double]$loadProperty.Value
                    }
                }
            )
            if ($loadValues.Count -gt 0) {
                [void]$samples.Add(($loadValues | Measure-Object -Average).Average)
            }

            if ($sampleIndex -lt [int]$CheckSettings.SampleCount) {
                Start-Sleep -Seconds ([int]$CheckSettings.SampleIntervalSeconds)
            }
        }

        $logicalProcessors = $null
        try {
            $computerSystem = if ($useCim) {
                Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            }
            else {
                Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            }
            $logicalProcessors = [int]$computerSystem.NumberOfLogicalProcessors
        }
        catch {
            $logicalProcessors = $null
        }

        $topProcesses = @(
            Get-Process -ErrorAction SilentlyContinue |
                Sort-Object -Property WorkingSet64 -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    [pscustomobject]@{
                        Name         = [string]$_.ProcessName
                        Id           = [int]$_.Id
                        WorkingSetMB = [math]::Round([double]$_.WorkingSet64 / 1MB, 1)
                    }
                }
        )

        [pscustomobject]@{
            Samples           = @($samples.ToArray())
            LogicalProcessors = $logicalProcessors
            TopProcesses      = $topProcesses
        }
    }

    $cpuState = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings)
    $stopwatch.Stop()

    $samples = @($cpuState.Samples | ForEach-Object { [math]::Round([double]$_, 1) })
    if ($samples.Count -eq 0) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'Cpu' -Category 'Capacity' -ComputerName $Context.ComputerName -Target 'Processor' -Message 'No processor load samples could be collected.' -Recommendation 'Validate Win32_Processor access on the target; LoadPercentage returned no values.' -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $averagePercent = [math]::Round((@($samples) | Measure-Object -Average).Average, 1)

    if ($averagePercent -ge [double]$Settings.CriticalPercent) {
        $status = 'Critical'
        $recommendation = 'Identify the drivers of the sustained load and rebalance, scale, or schedule the workload before it starves other services.'
    }
    elseif ($averagePercent -ge [double]$Settings.WarningPercent) {
        $status = 'Warning'
        $recommendation = 'Review the top processes and workload placement; sustained load at this level leaves little headroom.'
    }
    else {
        $status = 'Healthy'
        $recommendation = ''
    }

    $message = "Average CPU load $averagePercent% across $($samples.Count) sample(s)."
    $evidence = [ordered]@{
        AveragePercent    = $averagePercent
        Samples           = $samples
        SampleCount       = $samples.Count
        LogicalProcessors = $cpuState.LogicalProcessors
        TopProcesses      = @($cpuState.TopProcesses)
    }

    return New-InfraPulseResult -Status $status -CheckName 'Cpu' -Category 'Capacity' -ComputerName $Context.ComputerName -Target 'Processor' -Message $message -ObservedValue ("{0:N1}%" -f $averagePercent) -WarningThreshold (">= {0}%" -f $Settings.WarningPercent) -CriticalThreshold (">= {0}%" -f $Settings.CriticalPercent) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
