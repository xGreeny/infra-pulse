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

        # Commit charge: a host can suffocate at its commit limit while
        # physical memory still looks fine.
        $commitLimitBytes = [double]$operatingSystem.TotalVirtualMemorySize * 1KB
        $commitFreeBytes = [double]$operatingSystem.FreeVirtualMemory * 1KB
        $commitUsedPercent = if ($commitLimitBytes -gt 0) { (($commitLimitBytes - $commitFreeBytes) / $commitLimitBytes) * 100 } else { $null }

        $pageFileAllocatedMB = $null
        $pageFileUsedMB = $null
        try {
            $pageFiles = if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
                @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
            }
            else {
                @(Get-WmiObject -Class Win32_PageFileUsage -ErrorAction Stop)
            }
            if ($pageFiles.Count -gt 0) {
                $pageFileAllocatedMB = [double](@($pageFiles | Measure-Object -Property AllocatedBaseSize -Sum).Sum)
                $pageFileUsedMB = [double](@($pageFiles | Measure-Object -Property CurrentUsage -Sum).Sum)
            }
        }
        catch {
            $pageFileAllocatedMB = $null
            $pageFileUsedMB = $null
        }

        [pscustomobject]@{
            TotalBytes          = [math]::Round($totalBytes, 0)
            AvailableBytes      = [math]::Round($availableBytes, 0)
            TotalGB             = [math]::Round($totalBytes / 1GB, 2)
            AvailableGB         = [math]::Round($availableBytes / 1GB, 2)
            AvailablePercent    = [math]::Round($availablePercent, 2)
            CommitLimitGB       = [math]::Round($commitLimitBytes / 1GB, 2)
            CommitUsedGB        = [math]::Round(($commitLimitBytes - $commitFreeBytes) / 1GB, 2)
            CommitUsedPercent   = if ($null -ne $commitUsedPercent) { [math]::Round($commitUsedPercent, 2) } else { $null }
            PageFileAllocatedMB = $pageFileAllocatedMB
            PageFileUsedMB      = $pageFileUsedMB
        }
    }

    $memory = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    $availableSeverity = 0
    if ([double]$memory.AvailablePercent -le [double]$Settings.CriticalAvailablePercent) {
        $availableSeverity = 2
    }
    elseif ([double]$memory.AvailablePercent -le [double]$Settings.WarningAvailablePercent) {
        $availableSeverity = 1
    }

    # Older or mocked records may not carry the commit fields.
    $commitUsedPercent = $null
    $commitProperty = $memory.PSObject.Properties['CommitUsedPercent']
    if ($null -ne $commitProperty -and $null -ne $commitProperty.Value) {
        $commitUsedPercent = [double]$commitProperty.Value
    }

    $commitSeverity = 0
    if ($null -ne $commitUsedPercent) {
        if ($commitUsedPercent -ge [double]$Settings.CriticalCommitPercent) {
            $commitSeverity = 2
        }
        elseif ($commitUsedPercent -ge [double]$Settings.WarningCommitPercent) {
            $commitSeverity = 1
        }
    }

    $severity = [math]::Max($availableSeverity, $commitSeverity)
    $status = switch ($severity) {
        2 { 'Critical' }
        1 { 'Warning' }
        default { 'Healthy' }
    }
    $recommendation = if ($severity -eq 0) {
        ''
    }
    elseif ($commitSeverity -gt $availableSeverity) {
        'Commit charge approaches the limit; grow the page file, add memory, or reduce the committed workload before allocations start failing.'
    }
    elseif ($severity -eq 2) {
        'Identify memory pressure, runaway processes, or an undersized workload and restore operating headroom.'
    }
    else {
        'Review sustained memory consumption and confirm that paging and workload sizing are acceptable.'
    }

    $message = '{0:N2} GB available ({1:N2}%) of {2:N2} GB physical memory.' -f [double]$memory.AvailableGB, [double]$memory.AvailablePercent, [double]$memory.TotalGB
    if ($null -ne $commitUsedPercent -and $commitSeverity -gt 0) {
        $message += ' Commit charge at {0:N2}% of the limit.' -f $commitUsedPercent
    }

    $evidence = [ordered]@{
        TotalBytes       = [double]$memory.TotalBytes
        AvailableBytes   = [double]$memory.AvailableBytes
        TotalGB          = [double]$memory.TotalGB
        AvailableGB      = [double]$memory.AvailableGB
        AvailablePercent = [double]$memory.AvailablePercent
    }
    foreach ($commitField in @('CommitLimitGB', 'CommitUsedGB', 'CommitUsedPercent', 'PageFileAllocatedMB', 'PageFileUsedMB')) {
        $fieldProperty = $memory.PSObject.Properties[$commitField]
        if ($null -ne $fieldProperty) {
            $evidence[$commitField] = $fieldProperty.Value
        }
    }

    return New-InfraPulseResult -Status $status -CheckName 'Memory' -Category 'Capacity' -ComputerName $Context.ComputerName -Target 'Physical memory' -Message $message -ObservedValue ("{0:N2}%" -f [double]$memory.AvailablePercent) -WarningThreshold ("<= {0}% available or >= {1}% commit" -f $Settings.WarningAvailablePercent, $Settings.WarningCommitPercent) -CriticalThreshold ("<= {0}% available or >= {1}% commit" -f $Settings.CriticalAvailablePercent, $Settings.CriticalCommitPercent) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
