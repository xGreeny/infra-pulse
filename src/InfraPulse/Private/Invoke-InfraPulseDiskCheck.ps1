function Invoke-InfraPulseDiskCheck {
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
            throw 'The Disk check requires a Windows target.'
        }

        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
        }
        else {
            $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
        }

        $includePatterns = @($CheckSettings.Include)
        $excludePatterns = @($CheckSettings.Exclude)

        foreach ($disk in $disks) {
            $deviceId = [string]$disk.DeviceID
            $included = $includePatterns.Count -eq 0
            foreach ($pattern in $includePatterns) {
                if ($deviceId -like [string]$pattern) {
                    $included = $true
                    break
                }
            }

            $excluded = $false
            foreach ($pattern in $excludePatterns) {
                if ($deviceId -like [string]$pattern) {
                    $excluded = $true
                    break
                }
            }

            if (-not $included -or $excluded) {
                continue
            }

            $sizeBytes = [double]$disk.Size
            $freeBytes = [double]$disk.FreeSpace
            $freePercent = if ($sizeBytes -gt 0) { ($freeBytes / $sizeBytes) * 100 } else { 0 }

            [pscustomobject]@{
                DeviceId    = $deviceId
                VolumeName  = [string]$disk.VolumeName
                SizeBytes   = [math]::Round($sizeBytes, 0)
                FreeBytes   = [math]::Round($freeBytes, 0)
                FreeGB      = [math]::Round($freeBytes / 1GB, 2)
                FreePercent = [math]::Round($freePercent, 2)
                FileSystem  = [string]$disk.FileSystem
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $stopwatch.Stop()

    if ($raw.Count -eq 0) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'Disk' -Category 'Capacity' -ComputerName $Context.ComputerName -Target 'Fixed disks' -Message 'No fixed disks matched the configured include and exclude patterns.' -Recommendation 'Review Checks.Disk.Include and Checks.Disk.Exclude.' -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $results = @()
    foreach ($disk in $raw) {
        # A matching per-volume entry overrides individual thresholds; every
        # key it omits falls back to the global value.
        $volumeOverride = $null
        foreach ($volume in @($Settings.Volumes)) {
            if ([string]$disk.DeviceId -like [string]$volume.DeviceId) {
                $volumeOverride = $volume
                break
            }
        }
        $warningFreePercent = if ($null -ne $volumeOverride -and $volumeOverride.Contains('WarningFreePercent')) { [double]$volumeOverride.WarningFreePercent } else { [double]$Settings.WarningFreePercent }
        $criticalFreePercent = if ($null -ne $volumeOverride -and $volumeOverride.Contains('CriticalFreePercent')) { [double]$volumeOverride.CriticalFreePercent } else { [double]$Settings.CriticalFreePercent }
        $warningFreeGB = if ($null -ne $volumeOverride -and $volumeOverride.Contains('WarningFreeGB')) { [double]$volumeOverride.WarningFreeGB } else { [double]$Settings.WarningFreeGB }
        $criticalFreeGB = if ($null -ne $volumeOverride -and $volumeOverride.Contains('CriticalFreeGB')) { [double]$volumeOverride.CriticalFreeGB } else { [double]$Settings.CriticalFreeGB }

        # Thresholds are evaluated against unrounded values derived from the raw
        # byte counts; the rounded FreeGB/FreePercent fields remain display values.
        $exactFreeGB = [double]$disk.FreeBytes / 1GB
        $exactFreePercent = if ([double]$disk.SizeBytes -gt 0) { ([double]$disk.FreeBytes / [double]$disk.SizeBytes) * 100 } else { 0 }
        $isCritical = ($exactFreePercent -le $criticalFreePercent) -or ($exactFreeGB -le $criticalFreeGB)
        $isWarning = ($exactFreePercent -le $warningFreePercent) -or ($exactFreeGB -le $warningFreeGB)

        if ($isCritical) {
            $status = 'Critical'
            $recommendation = 'Free disk space immediately, extend the volume, or move data after validating retention and recovery requirements.'
        }
        elseif ($isWarning) {
            $status = 'Warning'
            $recommendation = 'Review growth, cleanup candidates, and volume capacity before the critical threshold is reached.'
        }
        else {
            $status = 'Healthy'
            $recommendation = ''
        }

        $volumeLabel = if ([string]::IsNullOrWhiteSpace([string]$disk.VolumeName)) { 'unlabeled' } else { [string]$disk.VolumeName }
        $message = '{0:N2} GB free ({1:N2}%) of {2:N2} GB on {3} ({4}).' -f [double]$disk.FreeGB, [double]$disk.FreePercent, ([double]$disk.SizeBytes / 1GB), [string]$disk.DeviceId, $volumeLabel
        $evidence = [ordered]@{
            DeviceId    = [string]$disk.DeviceId
            VolumeName  = [string]$disk.VolumeName
            FileSystem  = [string]$disk.FileSystem
            SizeBytes   = [double]$disk.SizeBytes
            FreeBytes   = [double]$disk.FreeBytes
            FreeGB      = [double]$disk.FreeGB
            FreePercent = [double]$disk.FreePercent
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'Disk' -Category 'Capacity' -ComputerName $Context.ComputerName -Target ([string]$disk.DeviceId) -Message $message -ObservedValue ("{0:N2}% / {1:N2} GB" -f [double]$disk.FreePercent, [double]$disk.FreeGB) -WarningThreshold ("<= {0}% or <= {1} GB" -f $warningFreePercent, $warningFreeGB) -CriticalThreshold ("<= {0}% or <= {1} GB" -f $criticalFreePercent, $criticalFreeGB) -Recommendation $recommendation -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / $raw.Count)
    }

    return $results
}
