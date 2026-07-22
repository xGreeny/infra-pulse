function Invoke-InfraPulseStabilityCheck {
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
            throw 'The Stability check requires a Windows target.'
        }

        $startTime = (Get-Date).AddDays(-[double]$CheckSettings.LookbackDays)
        $incidents = New-Object System.Collections.Generic.List[object]
        $queryErrors = New-Object System.Collections.Generic.List[string]
        $queriesAttempted = 0

        # Each indicator is queried separately so one unreadable provider does
        # not hide the others.
        $indicatorQueries = @(
            @{ Kind = 'Bugcheck'; Filter = @{ LogName = 'System'; StartTime = $startTime; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001 } }
            @{ Kind = 'Kernel power loss'; Filter = @{ LogName = 'System'; StartTime = $startTime; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 } }
            @{ Kind = 'Unexpected shutdown'; Filter = @{ LogName = 'System'; StartTime = $startTime; ProviderName = 'EventLog'; Id = 6008 } }
            @{ Kind = 'Hardware error (WHEA)'; Filter = @{ LogName = 'System'; StartTime = $startTime; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = @(1, 2) } }
        )

        foreach ($indicatorQuery in $indicatorQueries) {
            $queriesAttempted++
            try {
                $matchedEvents = @(Get-WinEvent -FilterHashtable $indicatorQuery.Filter -MaxEvents 50 -ErrorAction Stop)
                foreach ($matchedEvent in $matchedEvents) {
                    $incidentRecord = [pscustomobject]@{
                        Kind        = [string]$indicatorQuery.Kind
                        TimeCreated = $matchedEvent.TimeCreated
                        Id          = [int]$matchedEvent.Id
                        Provider    = [string]$matchedEvent.ProviderName
                    }
                    [void]$incidents.Add($incidentRecord)
                }
            }
            catch {
                if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                    [void]$queryErrors.Add("$($indicatorQuery.Kind): $($_.Exception.Message)")
                }
            }
        }

        $minidumpCount = $null
        try {
            $minidumpPath = Join-Path -Path $env:SystemRoot -ChildPath 'Minidump'
            if (Test-Path -LiteralPath $minidumpPath) {
                $minidumpCount = @(Get-ChildItem -LiteralPath $minidumpPath -Filter '*.dmp' -File -ErrorAction Stop).Count
            }
            else {
                $minidumpCount = 0
            }
        }
        catch {
            $minidumpCount = $null
        }

        [pscustomobject]@{
            Incidents        = @($incidents.ToArray())
            MinidumpCount    = $minidumpCount
            QueriesAttempted = $queriesAttempted
            QueryErrors      = @($queryErrors.ToArray())
        }
    }

    $stability = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings)
    $stopwatch.Stop()

    $incidents = @($stability.Incidents | Sort-Object -Property TimeCreated -Descending)
    $queryErrors = @($stability.QueryErrors)
    $incidentCount = $incidents.Count

    if ($queryErrors.Count -ge [int]$stability.QueriesAttempted -and $incidentCount -eq 0) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'Stability' -Category 'Reliability' -ComputerName $Context.ComputerName -Target 'Operating system' -Message 'Crash indicators could not be queried.' -Recommendation 'Validate System event log read access; every indicator query failed.' -Evidence ([ordered]@{ QueryErrors = $queryErrors }) -DurationMs $stopwatch.Elapsed.TotalMilliseconds -ErrorMessage ($queryErrors -join '; ')
    }

    if ($incidentCount -ge [int]$Settings.CriticalCount) {
        $status = 'Critical'
        $message = "$incidentCount crash indicator(s) in the last $($Settings.LookbackDays) day(s)."
        $recommendation = 'Correlate bugchecks, power-loss events, and hardware errors with driver, firmware, and hardware diagnostics before the host degrades further.'
    }
    elseif ($incidentCount -ge [int]$Settings.WarningCount) {
        $status = 'Warning'
        $message = "$incidentCount crash indicator(s) in the last $($Settings.LookbackDays) day(s)."
        $recommendation = 'Review the incident evidence and check minidumps, recent driver changes, and power events.'
    }
    else {
        $status = 'Healthy'
        $message = "No crash indicators in the last $($Settings.LookbackDays) day(s)."
        $recommendation = ''
    }

    $evidence = [ordered]@{
        IncidentCount = $incidentCount
        LookbackDays  = [double]$Settings.LookbackDays
        Incidents     = @($incidents | Select-Object -First 25)
        MinidumpCount = $stability.MinidumpCount
        QueryErrors   = $queryErrors
    }

    return New-InfraPulseResult -Status $status -CheckName 'Stability' -Category 'Reliability' -ComputerName $Context.ComputerName -Target 'Operating system' -Message $message -ObservedValue $incidentCount -WarningThreshold (">= {0} incident(s)" -f $Settings.WarningCount) -CriticalThreshold (">= {0} incident(s)" -f $Settings.CriticalCount) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
