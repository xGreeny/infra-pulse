function Invoke-InfraPulseUptimeCheck {
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
            throw 'The Uptime check requires a Windows target.'
        }

        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $lastBoot = [datetime]$operatingSystem.LastBootUpTime
        }
        else {
            $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $lastBoot = [System.Management.ManagementDateTimeConverter]::ToDateTime($operatingSystem.LastBootUpTime)
        }

        $uptime = (Get-Date) - $lastBoot
        [pscustomobject]@{
            LastBootTime = $lastBoot
            UptimeDays   = [math]::Round($uptime.TotalDays, 2)
            UptimeHours  = [math]::Round($uptime.TotalHours, 2)
        }
    }

    $uptime = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if ([double]$uptime.UptimeDays -ge [double]$Settings.CriticalDays) {
        $status = 'Critical'
        $recommendation = 'Confirm patch compliance and schedule a controlled restart with an approved rollback and validation plan.'
    }
    elseif ([double]$uptime.UptimeDays -ge [double]$Settings.WarningDays) {
        $status = 'Warning'
        $recommendation = 'Review maintenance cadence and schedule a controlled restart if required by patching or operational policy.'
    }
    else {
        $status = 'Healthy'
        $recommendation = ''
    }

    $lastBootText = ([datetime]$uptime.LastBootTime).ToString('yyyy-MM-dd HH:mm:ss K')
    $message = '{0:N2} days since last boot ({1}).' -f [double]$uptime.UptimeDays, $lastBootText
    $evidence = [ordered]@{
        LastBootTime = [datetime]$uptime.LastBootTime
        UptimeDays   = [double]$uptime.UptimeDays
        UptimeHours  = [double]$uptime.UptimeHours
    }

    return New-InfraPulseResult -Status $status -CheckName 'Uptime' -Category 'Lifecycle' -ComputerName $Context.ComputerName -Target 'Operating system' -Message $message -ObservedValue ("{0:N2} days" -f [double]$uptime.UptimeDays) -WarningThreshold (">= {0} days" -f $Settings.WarningDays) -CriticalThreshold (">= {0} days" -f $Settings.CriticalDays) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
