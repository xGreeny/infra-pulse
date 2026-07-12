function Invoke-InfraPulseEventLogCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $logs = @($Settings.Logs)
    if ($logs.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'EventLog' -Category 'Reliability' -ComputerName $Context.ComputerName -Target 'Windows event logs' -Message 'No Windows event logs are configured.' -Recommendation 'Add log names under Checks.EventLog.Logs.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        param($CheckSettings)

        if ($env:OS -ne 'Windows_NT') {
            throw 'The EventLog check requires a Windows target.'
        }

        $startTime = (Get-Date).AddHours(-[double]$CheckSettings.LookbackHours)
        foreach ($logName in @($CheckSettings.Logs)) {
            try {
                $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
            }
            catch {
                [pscustomobject]@{
                    LogName       = [string]$logName
                    Exists        = $false
                    QuerySucceeded = $false
                    Count         = 0
                    RetrievedCount = 0
                    Truncated     = $false
                    TopProviders  = @()
                    Samples       = @()
                    Error         = $_.Exception.Message
                }
                continue
            }

            $filter = @{
                LogName   = [string]$logName
                StartTime = $startTime
            }
            if (@($CheckSettings.Levels).Count -gt 0) {
                $filter.Level = @($CheckSettings.Levels)
            }

            try {
                $queriedEvents = @(Get-WinEvent -FilterHashtable $filter -MaxEvents ([int]$CheckSettings.MaxEvents) -ErrorAction Stop)
            }
            catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                    $queriedEvents = @()
                }
                else {
                    [pscustomobject]@{
                        LogName       = [string]$logName
                        Exists        = $true
                        QuerySucceeded = $false
                        Count         = 0
                        RetrievedCount = 0
                        Truncated     = $false
                        TopProviders  = @()
                        Samples       = @()
                        Error         = $_.Exception.Message
                    }
                    continue
                }
            }

            $retrievedCount = $queriedEvents.Count
            $truncated = $retrievedCount -ge [int]$CheckSettings.MaxEvents
            $events = @($queriedEvents)

            if (@($CheckSettings.ExcludeProviders).Count -gt 0) {
                $events = @($events | Where-Object { $_.ProviderName -notin @($CheckSettings.ExcludeProviders) })
            }
            if (@($CheckSettings.ExcludeEventIds).Count -gt 0) {
                $events = @($events | Where-Object { $_.Id -notin @($CheckSettings.ExcludeEventIds) })
            }

            $topProviders = @(
                $events |
                    Group-Object -Property ProviderName |
                    Sort-Object -Property Count -Descending |
                    Select-Object -First 5 |
                    ForEach-Object {
                        [pscustomobject]@{
                            Provider = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { '<unknown>' } else { [string]$_.Name }
                            Count    = [int]$_.Count
                        }
                    }
            )

            $samples = @()
            foreach ($event in @($events | Select-Object -First 5)) {
                $message = $null
                if ([bool]$CheckSettings.IncludeMessages) {
                    try {
                        $message = ([string]$event.Message -replace '[\r\n]+', ' ').Trim()
                        if ($message.Length -gt 300) {
                            $message = $message.Substring(0, 300) + '...'
                        }
                    }
                    catch {
                        $message = $null
                    }
                }

                $samples += [pscustomobject]@{
                    TimeCreated  = $event.TimeCreated
                    Id           = [int]$event.Id
                    Level        = [string]$event.LevelDisplayName
                    ProviderName = [string]$event.ProviderName
                    Message      = $message
                }
            }

            [pscustomobject]@{
                LogName        = [string]$logName
                Exists         = $true
                QuerySucceeded = $true
                Count          = $events.Count
                RetrievedCount = $retrievedCount
                Truncated      = $truncated
                TopProviders   = $topProviders
                Samples        = $samples
                Error          = $null
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $stopwatch.Stop()

    $results = @()
    foreach ($log in $raw) {
        $querySucceeded = $true
        if ($null -ne $log.PSObject.Properties['QuerySucceeded']) {
            $querySucceeded = [bool]$log.QuerySucceeded
        }

        if (-not [bool]$log.Exists) {
            $status = 'Unknown'
            $message = "Windows event log '$($log.LogName)' is unavailable."
            $recommendation = 'Validate the configured log name and the account permission to read that log.'
        }
        elseif (-not $querySucceeded) {
            $status = 'Unknown'
            $message = "Windows event log '$($log.LogName)' could not be queried."
            $recommendation = 'Validate event-log read permissions and inspect the query error captured in the result evidence.'
        }
        elseif ([int]$log.Count -ge [int]$Settings.CriticalCount) {
            $status = 'Critical'
            $message = "$($log.Count) critical/error event(s) in '$($log.LogName)' during the last $($Settings.LookbackHours) hour(s)."
            $recommendation = 'Triage the highest-volume providers and correlate events with service impact and recent changes.'
        }
        elseif ([int]$log.Count -ge [int]$Settings.WarningCount) {
            $status = 'Warning'
            $message = "$($log.Count) critical/error event(s) in '$($log.LogName)' during the last $($Settings.LookbackHours) hour(s)."
            $recommendation = 'Review recurring providers and event IDs before the error rate becomes operationally significant.'
        }
        elseif ([bool]$log.Truncated) {
            $status = 'Unknown'
            $message = "The '$($log.LogName)' query reached the configured limit of $($Settings.MaxEvents) event(s); $($log.Count) event(s) matched after exclusions."
            $recommendation = 'Increase Checks.EventLog.MaxEvents or narrow the lookback window before treating the event volume as healthy.'
        }
        else {
            $status = 'Healthy'
            $message = "$($log.Count) critical/error event(s) in '$($log.LogName)' during the last $($Settings.LookbackHours) hour(s)."
            $recommendation = ''
        }

        $retrievedCount = [int]$log.Count
        if ($null -ne $log.PSObject.Properties['RetrievedCount']) {
            $retrievedCount = [int]$log.RetrievedCount
        }

        $evidence = [ordered]@{
            LogName        = [string]$log.LogName
            Count          = [int]$log.Count
            RetrievedCount = $retrievedCount
            LookbackHours  = [double]$Settings.LookbackHours
            Levels         = @($Settings.Levels)
            Truncated      = [bool]$log.Truncated
            TopProviders   = @($log.TopProviders)
            Samples        = @($log.Samples)
            QueryError     = [string]$log.Error
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'EventLog' -Category 'Reliability' -ComputerName $Context.ComputerName -Target ([string]$log.LogName) -Message $message -ObservedValue ([int]$log.Count) -WarningThreshold (">= {0} events" -f $Settings.WarningCount) -CriticalThreshold (">= {0} events" -f $Settings.CriticalCount) -Recommendation $recommendation -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / [math]::Max($raw.Count, 1)) -ErrorMessage ([string]$log.Error)
    }

    return $results
}
