function Invoke-InfraPulseStorageCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    # The Storage check has no tunable settings beyond Enabled; the parameter keeps the shared check signature.
    $null = $Settings

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        if ($env:OS -ne 'Windows_NT') {
            throw 'The Storage check requires a Windows target.'
        }

        if (-not (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue) -or -not (Get-Command -Name Get-Volume -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{
                Supported = $false
                Disks     = @()
                Volumes   = @()
            }
        }

        $disks = @(
            Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    FriendlyName      = [string]$_.FriendlyName
                    MediaType         = [string]$_.MediaType
                    HealthStatus      = [string]$_.HealthStatus
                    OperationalStatus = (@($_.OperationalStatus) -join ', ')
                    SizeGB            = [math]::Round([double]$_.Size / 1GB, 2)
                }
            }
        )

        $volumes = @(
            Get-Volume -ErrorAction Stop |
                Where-Object { [string]$_.DriveType -eq 'Fixed' } |
                ForEach-Object {
                    [pscustomobject]@{
                        DriveLetter     = [string]$_.DriveLetter
                        FileSystemLabel = [string]$_.FileSystemLabel
                        FileSystem      = [string]$_.FileSystem
                        HealthStatus    = [string]$_.HealthStatus
                    }
                }
        )

        [pscustomobject]@{
            Supported = $true
            Disks     = $disks
            Volumes   = $volumes
        }
    }

    $storage = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if (-not [bool]$storage.Supported) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'Storage' -Category 'Reliability' -ComputerName $Context.ComputerName -Target 'Storage health' -Message 'Storage health interfaces are unavailable on the target.' -Recommendation 'Get-PhysicalDisk and Get-Volume require the Storage module (Windows Server 2012 / Windows 8 or later).' -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $disks = @($storage.Disks)
    $volumes = @($storage.Volumes)
    $results = @()
    $unhealthyCount = 0

    foreach ($disk in $disks) {
        $healthStatus = [string]$disk.HealthStatus
        if ($healthStatus -eq 'Healthy' -or [string]::IsNullOrWhiteSpace($healthStatus)) {
            continue
        }
        $unhealthyCount++
        $status = if ($healthStatus -eq 'Warning') { 'Warning' } else { 'Critical' }
        $evidence = [ordered]@{
            FriendlyName      = [string]$disk.FriendlyName
            MediaType         = [string]$disk.MediaType
            HealthStatus      = $healthStatus
            OperationalStatus = [string]$disk.OperationalStatus
            SizeGB            = $disk.SizeGB
        }
        $results += New-InfraPulseResult -Status $status -CheckName 'Storage' -Category 'Reliability' -ComputerName $Context.ComputerName -Target ([string]$disk.FriendlyName) -Message "Physical disk '$($disk.FriendlyName)' reports health status '$healthStatus' ($($disk.OperationalStatus))." -ObservedValue $healthStatus -CriticalThreshold 'Health status must be Healthy' -Recommendation 'Check hardware diagnostics, controller state, and vendor tooling; plan a replacement before the disk fails.' -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / [math]::Max($disks.Count + $volumes.Count, 1))
    }

    foreach ($volume in $volumes) {
        $healthStatus = [string]$volume.HealthStatus
        if ($healthStatus -eq 'Healthy' -or [string]::IsNullOrWhiteSpace($healthStatus)) {
            continue
        }
        $unhealthyCount++
        $status = if ($healthStatus -eq 'Warning') { 'Warning' } else { 'Critical' }
        $volumeLabel = if ([string]::IsNullOrWhiteSpace([string]$volume.DriveLetter)) { [string]$volume.FileSystemLabel } else { "$($volume.DriveLetter):" }
        $evidence = [ordered]@{
            DriveLetter     = [string]$volume.DriveLetter
            FileSystemLabel = [string]$volume.FileSystemLabel
            FileSystem      = [string]$volume.FileSystem
            HealthStatus    = $healthStatus
        }
        $results += New-InfraPulseResult -Status $status -CheckName 'Storage' -Category 'Reliability' -ComputerName $Context.ComputerName -Target $volumeLabel -Message "Volume '$volumeLabel' reports health status '$healthStatus'." -ObservedValue $healthStatus -CriticalThreshold 'Health status must be Healthy' -Recommendation 'Run a file-system check during a maintenance window and validate the underlying disk health.' -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / [math]::Max($disks.Count + $volumes.Count, 1))
    }

    $summaryEvidence = [ordered]@{
        PhysicalDisks    = @($disks)
        FixedVolumes     = @($volumes)
        UnhealthyObjects = $unhealthyCount
    }
    $results += New-InfraPulseResult -Status 'Healthy' -CheckName 'Storage' -Category 'Reliability' -ComputerName $Context.ComputerName -Target 'Storage inventory' -Message "$($disks.Count - @($disks | Where-Object { [string]$_.HealthStatus -notin @('Healthy', '') }).Count) of $($disks.Count) physical disk(s) and $($volumes.Count - @($volumes | Where-Object { [string]$_.HealthStatus -notin @('Healthy', '') }).Count) of $($volumes.Count) fixed volume(s) report healthy status." -ObservedValue ($disks.Count + $volumes.Count - $unhealthyCount) -CriticalThreshold 'Health status must be Healthy' -Evidence $summaryEvidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds

    return $results
}
