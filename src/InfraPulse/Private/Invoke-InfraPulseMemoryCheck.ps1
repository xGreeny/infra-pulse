function Invoke-InfraPulseMemoryCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        if ($env:OS -ne 'Windows_NT') {
            throw 'The Memory check requires a Windows target.'
        }

        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }
        else {
            $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        }

        $totalBytes = [double]$operatingSystem.TotalVisibleMemorySize * 1KB
        $availableBytes = [double]$operatingSystem.FreePhysicalMemory * 1KB
        $availablePercent = if ($totalBytes -gt 0) { ($availableBytes / $totalBytes) * 100 } else { 0 }

        [pscustomobject]@{
            TotalBytes       = [math]::Round($totalBytes, 0)
            AvailableBytes   = [math]::Round($availableBytes, 0)
            TotalGB          = [math]::Round($totalBytes / 1GB, 2)
            AvailableGB      = [math]::Round($availableBytes / 1GB, 2)
            AvailablePercent = [math]::Round($availablePercent, 2)
        }
    }

    $memory = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if ([double]$memory.AvailablePercent -le [double]$Settings.CriticalAvailablePercent) {
        $status = 'Critical'
        $recommendation = 'Identify memory pressure, runaway processes, or an undersized workload and restore operating headroom.'
    }
    elseif ([double]$memory.AvailablePercent -le [double]$Settings.WarningAvailablePercent) {
        $status = 'Warning'
        $recommendation = 'Review sustained memory consumption and confirm that paging and workload sizing are acceptable.'
    }
    else {
        $status = 'Healthy'
        $recommendation = ''
    }

    $message = '{0:N2} GB available ({1:N2}%) of {2:N2} GB physical memory.' -f [double]$memory.AvailableGB, [double]$memory.AvailablePercent, [double]$memory.TotalGB
    $evidence = [ordered]@{
        TotalBytes       = [double]$memory.TotalBytes
        AvailableBytes   = [double]$memory.AvailableBytes
        TotalGB          = [double]$memory.TotalGB
        AvailableGB      = [double]$memory.AvailableGB
        AvailablePercent = [double]$memory.AvailablePercent
    }

    return New-InfraPulseResult -Status $status -CheckName 'Memory' -Category 'Capacity' -ComputerName $Context.ComputerName -Target 'Physical memory' -Message $message -ObservedValue ("{0:N2}%" -f [double]$memory.AvailablePercent) -WarningThreshold ("<= {0}%" -f $Settings.WarningAvailablePercent) -CriticalThreshold ("<= {0}%" -f $Settings.CriticalAvailablePercent) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
