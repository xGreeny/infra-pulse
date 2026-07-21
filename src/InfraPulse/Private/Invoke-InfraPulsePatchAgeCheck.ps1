function Invoke-InfraPulsePatchAgeCheck {
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
            throw 'The PatchAge check requires a Windows target.'
        }

        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            $hotfixes = @(Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop)
        }
        else {
            $hotfixes = @(Get-WmiObject -Class Win32_QuickFixEngineering -ErrorAction Stop)
        }

        $patches = foreach ($hotfix in $hotfixes) {
            # InstalledOn arrives as DateTime through CIM but as a culture-bound
            # string through WMI, and can be absent entirely; only entries with
            # a resolvable date participate in the age evaluation.
            $installedOnProperty = $hotfix.PSObject.Properties['InstalledOn']
            if ($null -eq $installedOnProperty -or $null -eq $installedOnProperty.Value) {
                continue
            }

            $installedOn = $null
            if ($installedOnProperty.Value -is [datetime]) {
                $installedOn = [datetime]$installedOnProperty.Value
            }
            else {
                $parsed = [datetime]::MinValue
                $styles = [System.Globalization.DateTimeStyles]::None
                if ([datetime]::TryParse([string]$installedOnProperty.Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
                    $installedOn = $parsed
                }
                elseif ([datetime]::TryParse([string]$installedOnProperty.Value, [System.Globalization.CultureInfo]::CurrentCulture, $styles, [ref]$parsed)) {
                    $installedOn = $parsed
                }
            }
            if ($null -eq $installedOn) {
                continue
            }

            [pscustomobject]@{
                HotFixId    = [string]$hotfix.HotFixID
                Description = [string]$hotfix.Description
                InstalledOn = $installedOn
            }
        }

        $ordered = @($patches | Sort-Object -Property InstalledOn -Descending)
        $latest = if ($ordered.Count -gt 0) { $ordered[0] } else { $null }

        [pscustomobject]@{
            TotalPatches  = $ordered.Count
            LastPatchDate = if ($null -ne $latest) { [datetime]$latest.InstalledOn } else { $null }
            LastPatchId   = if ($null -ne $latest) { [string]$latest.HotFixId } else { $null }
            RecentPatches = @(
                $ordered |
                    Select-Object -First 5 |
                    ForEach-Object {
                        [pscustomobject]@{
                            HotFixId    = $_.HotFixId
                            Description = $_.Description
                            InstalledOn = $_.InstalledOn
                        }
                    }
            )
        }
    }

    $patchState = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if ($null -eq $patchState.LastPatchDate) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'PatchAge' -Category 'Lifecycle' -ComputerName $Context.ComputerName -Target 'Operating system' -Message 'No dated update installations could be determined.' -Recommendation 'Validate update history access on the target; Win32_QuickFixEngineering returned no entries with an installation date.' -Evidence ([ordered]@{ TotalPatches = [int]$patchState.TotalPatches }) -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $daysSince = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]$patchState.LastPatchDate).ToUniversalTime()).TotalDays, 2)

    if ($daysSince -ge [double]$Settings.CriticalDays) {
        $status = 'Critical'
        $recommendation = 'Install pending updates through the approved patch process; the target has fallen far behind the expected cadence.'
    }
    elseif ($daysSince -ge [double]$Settings.WarningDays) {
        $status = 'Warning'
        $recommendation = 'Schedule the next patch window; the last update installation is older than the expected cadence.'
    }
    else {
        $status = 'Healthy'
        $recommendation = ''
    }

    $message = "Last update ($($patchState.LastPatchId)) was installed $([math]::Round($daysSince, 0)) day(s) ago on $(([datetime]$patchState.LastPatchDate).ToString('yyyy-MM-dd'))."
    $evidence = [ordered]@{
        LastPatchDate = [datetime]$patchState.LastPatchDate
        LastPatchId   = [string]$patchState.LastPatchId
        DaysSince     = $daysSince
        TotalPatches  = [int]$patchState.TotalPatches
        RecentPatches = @($patchState.RecentPatches)
    }

    return New-InfraPulseResult -Status $status -CheckName 'PatchAge' -Category 'Lifecycle' -ComputerName $Context.ComputerName -Target 'Operating system' -Message $message -ObservedValue ("{0:N2} days" -f $daysSince) -WarningThreshold (">= {0} days" -f $Settings.WarningDays) -CriticalThreshold (">= {0} days" -f $Settings.CriticalDays) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
