function Test-InfraPulseConfigurationData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Configuration
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $catalog = @(Get-InfraPulseCheckCatalog)
    $validChecks = @($catalog.Name)

    if (-not $Configuration.Contains('SchemaVersion')) {
        [void]$errors.Add('SchemaVersion is required.')
    }
    elseif ([string]$Configuration.SchemaVersion -ne '1.0') {
        [void]$errors.Add("Unsupported SchemaVersion '$($Configuration.SchemaVersion)'. Supported version: 1.0.")
    }

    if (-not $Configuration.Contains('General') -or -not ($Configuration.General -is [System.Collections.IDictionary])) {
        [void]$errors.Add('General must be a hashtable.')
    }
    else {
        $general = $Configuration.General
        if (-not $general.Contains('DefaultChecks')) {
            [void]$errors.Add('General.DefaultChecks is required.')
        }
        else {
            foreach ($check in @($general.DefaultChecks)) {
                if ([string]$check -notin $validChecks) {
                    [void]$errors.Add("General.DefaultChecks contains unknown check '$check'.")
                }
            }
        }

        if (-not $general.Contains('ConnectionTimeoutSeconds') -or -not (Test-InfraPulseNumber -Value $general.ConnectionTimeoutSeconds -Minimum 1 -Maximum 300)) {
            [void]$errors.Add('General.ConnectionTimeoutSeconds must be between 1 and 300.')
        }

        foreach ($booleanName in @('ContinueOnError', 'IncludeInventory')) {
            if (-not $general.Contains($booleanName) -or -not ($general[$booleanName] -is [bool])) {
                [void]$errors.Add("General.$booleanName must be Boolean.")
            }
        }
    }

    if (-not $Configuration.Contains('Checks') -or -not ($Configuration.Checks -is [System.Collections.IDictionary])) {
        [void]$errors.Add('Checks must be a hashtable.')
    }
    else {
        $checks = $Configuration.Checks
        foreach ($key in $checks.Keys) {
            if ([string]$key -notin $validChecks) {
                [void]$warnings.Add("Checks contains unknown section '$key'; it will not be executed.")
            }
        }

        foreach ($checkName in $validChecks) {
            if (-not $checks.Contains($checkName) -or -not ($checks[$checkName] -is [System.Collections.IDictionary])) {
                [void]$errors.Add("Checks.$checkName must be a hashtable.")
                continue
            }

            if (-not $checks[$checkName].Contains('Enabled') -or -not ($checks[$checkName].Enabled -is [bool])) {
                [void]$errors.Add("Checks.$checkName.Enabled must be Boolean.")
            }
        }

        if ($checks.Contains('Disk')) {
            $disk = $checks.Disk
            foreach ($name in @('WarningFreePercent', 'CriticalFreePercent')) {
                if (-not $disk.Contains($name) -or -not (Test-InfraPulseNumber -Value $disk[$name] -Minimum 0 -Maximum 100)) {
                    [void]$errors.Add("Checks.Disk.$name must be between 0 and 100.")
                }
            }
            foreach ($name in @('WarningFreeGB', 'CriticalFreeGB')) {
                if (-not $disk.Contains($name) -or -not (Test-InfraPulseNumber -Value $disk[$name] -Minimum 0)) {
                    [void]$errors.Add("Checks.Disk.$name must be zero or greater.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $disk.WarningFreePercent) -and
                (Test-InfraPulseNumber -Value $disk.CriticalFreePercent) -and
                [double]$disk.CriticalFreePercent -gt [double]$disk.WarningFreePercent
            ) {
                [void]$errors.Add('Checks.Disk.CriticalFreePercent must be less than or equal to WarningFreePercent.')
            }
            if (
                (Test-InfraPulseNumber -Value $disk.WarningFreeGB) -and
                (Test-InfraPulseNumber -Value $disk.CriticalFreeGB) -and
                [double]$disk.CriticalFreeGB -gt [double]$disk.WarningFreeGB
            ) {
                [void]$errors.Add('Checks.Disk.CriticalFreeGB must be less than or equal to WarningFreeGB.')
            }
        }

        if ($checks.Contains('Memory')) {
            $memory = $checks.Memory
            foreach ($name in @('WarningAvailablePercent', 'CriticalAvailablePercent')) {
                if (-not $memory.Contains($name) -or -not (Test-InfraPulseNumber -Value $memory[$name] -Minimum 0 -Maximum 100)) {
                    [void]$errors.Add("Checks.Memory.$name must be between 0 and 100.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $memory.WarningAvailablePercent) -and
                (Test-InfraPulseNumber -Value $memory.CriticalAvailablePercent) -and
                [double]$memory.CriticalAvailablePercent -gt [double]$memory.WarningAvailablePercent
            ) {
                [void]$errors.Add('Checks.Memory.CriticalAvailablePercent must be less than or equal to WarningAvailablePercent.')
            }
        }

        if ($checks.Contains('Uptime')) {
            $uptime = $checks.Uptime
            foreach ($name in @('WarningDays', 'CriticalDays')) {
                if (-not $uptime.Contains($name) -or -not (Test-InfraPulseNumber -Value $uptime[$name] -Minimum 0)) {
                    [void]$errors.Add("Checks.Uptime.$name must be zero or greater.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $uptime.WarningDays) -and
                (Test-InfraPulseNumber -Value $uptime.CriticalDays) -and
                [double]$uptime.CriticalDays -lt [double]$uptime.WarningDays
            ) {
                [void]$errors.Add('Checks.Uptime.CriticalDays must be greater than or equal to WarningDays.')
            }
        }

        if ($checks.Contains('PendingReboot')) {
            $pending = $checks.PendingReboot
            if (-not $pending.Contains('PendingStatus') -or [string]$pending.PendingStatus -notin @('Warning', 'Critical')) {
                [void]$errors.Add('Checks.PendingReboot.PendingStatus must be Warning or Critical.')
            }
        }

        if ($checks.Contains('Services')) {
            $services = $checks.Services
            if (-not $services.Contains('Required')) {
                [void]$errors.Add('Checks.Services.Required is required.')
            }
            else {
                $index = 0
                foreach ($service in @($services.Required)) {
                    if (-not ($service -is [System.Collections.IDictionary])) {
                        [void]$errors.Add("Checks.Services.Required[$index] must be a hashtable.")
                    }
                    else {
                        if (-not $service.Contains('Name') -or [string]::IsNullOrWhiteSpace([string]$service.Name)) {
                            [void]$errors.Add("Checks.Services.Required[$index].Name is required.")
                        }
                        if (-not $service.Contains('ExpectedStatus') -or [string]$service.ExpectedStatus -notin @('Running', 'Stopped', 'Paused')) {
                            [void]$errors.Add("Checks.Services.Required[$index].ExpectedStatus must be Running, Stopped, or Paused.")
                        }
                        if (-not $service.Contains('Severity') -or [string]$service.Severity -notin @('Warning', 'Critical')) {
                            [void]$errors.Add("Checks.Services.Required[$index].Severity must be Warning or Critical.")
                        }
                    }
                    $index++
                }
            }
        }

        if ($checks.Contains('Certificates')) {
            $certificates = $checks.Certificates
            foreach ($name in @('WarningDays', 'CriticalDays')) {
                if (-not $certificates.Contains($name) -or -not (Test-InfraPulseNumber -Value $certificates[$name] -Minimum 0)) {
                    [void]$errors.Add("Checks.Certificates.$name must be zero or greater.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $certificates.WarningDays) -and
                (Test-InfraPulseNumber -Value $certificates.CriticalDays) -and
                [double]$certificates.CriticalDays -gt [double]$certificates.WarningDays
            ) {
                [void]$errors.Add('Checks.Certificates.CriticalDays must be less than or equal to WarningDays.')
            }
            foreach ($storePath in @($certificates.StorePaths)) {
                if ([string]$storePath -notlike 'Cert:\*') {
                    [void]$errors.Add("Checks.Certificates.StorePaths contains invalid certificate provider path '$storePath'.")
                }
            }
            foreach ($patternName in @('SubjectExcludePatterns', 'IssuerExcludePatterns')) {
                foreach ($pattern in @($certificates[$patternName])) {
                    if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
                        [void]$errors.Add("Checks.Certificates.$patternName cannot contain an empty pattern.")
                    }
                }
            }
            if (-not $certificates.Contains('RequirePrivateKey') -or -not ($certificates.RequirePrivateKey -is [bool])) {
                [void]$errors.Add('Checks.Certificates.RequirePrivateKey must be Boolean.')
            }
            if (-not $certificates.Contains('MinTotalLifetimeDays') -or -not (Test-InfraPulseNumber -Value $certificates.MinTotalLifetimeDays -Minimum 0)) {
                [void]$errors.Add('Checks.Certificates.MinTotalLifetimeDays must be zero or greater.')
            }
        }

        if ($checks.Contains('EventLog')) {
            $eventLog = $checks.EventLog
            if (-not $eventLog.Contains('LookbackHours') -or -not (Test-InfraPulseNumber -Value $eventLog.LookbackHours -Minimum 0.01 -Maximum 8760)) {
                [void]$errors.Add('Checks.EventLog.LookbackHours must be greater than zero and no greater than 8760.')
            }
            foreach ($name in @('WarningCount', 'CriticalCount')) {
                if (-not $eventLog.Contains($name) -or -not (Test-InfraPulseNumber -Value $eventLog[$name] -Minimum 0)) {
                    [void]$errors.Add("Checks.EventLog.$name must be zero or greater.")
                }
            }
            if (-not $eventLog.Contains('MaxEvents') -or -not (Test-InfraPulseNumber -Value $eventLog.MaxEvents -Minimum 1 -Maximum 50000)) {
                [void]$errors.Add('Checks.EventLog.MaxEvents must be between 1 and 50000.')
            }
            foreach ($level in @($eventLog.Levels)) {
                if (-not (Test-InfraPulseNumber -Value $level -Minimum 1 -Maximum 5)) {
                    [void]$errors.Add("Checks.EventLog.Levels contains invalid level '$level'; valid levels are 1 through 5.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $eventLog.WarningCount) -and
                (Test-InfraPulseNumber -Value $eventLog.CriticalCount) -and
                [double]$eventLog.CriticalCount -lt [double]$eventLog.WarningCount
            ) {
                [void]$errors.Add('Checks.EventLog.CriticalCount must be greater than or equal to WarningCount.')
            }
            if (
                (Test-InfraPulseNumber -Value $eventLog.MaxEvents) -and
                (Test-InfraPulseNumber -Value $eventLog.CriticalCount) -and
                [double]$eventLog.MaxEvents -lt [double]$eventLog.CriticalCount
            ) {
                [void]$warnings.Add('Checks.EventLog.MaxEvents is lower than CriticalCount; a truncated query may understate severity.')
            }
            if (-not $eventLog.Contains('IncludeMessages') -or -not ($eventLog.IncludeMessages -is [bool])) {
                [void]$errors.Add('Checks.EventLog.IncludeMessages must be Boolean.')
            }
        }

        if ($checks.Contains('Dns')) {
            $dns = $checks.Dns
            if (-not $dns.Contains('QueryType') -or [string]$dns.QueryType -notin @('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT')) {
                [void]$errors.Add('Checks.Dns.QueryType must be A, AAAA, CNAME, MX, NS, PTR, SRV, or TXT.')
            }
            foreach ($target in @($dns.Targets)) {
                if ($target -is [string]) {
                    if ([string]::IsNullOrWhiteSpace($target)) {
                        [void]$errors.Add('Checks.Dns.Targets cannot contain an empty string.')
                    }
                }
                elseif ($target -is [System.Collections.IDictionary]) {
                    if (-not $target.Contains('Name') -or [string]::IsNullOrWhiteSpace([string]$target.Name)) {
                        [void]$errors.Add('Each Checks.Dns.Targets hashtable requires Name.')
                    }
                    if ($target.Contains('Type') -and [string]$target.Type -notin @('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT')) {
                        [void]$errors.Add("Checks.Dns.Targets contains invalid query type '$($target.Type)'.")
                    }
                }
                else {
                    [void]$errors.Add('Checks.Dns.Targets entries must be strings or hashtables.')
                }
            }
        }

        if ($checks.Contains('Tcp')) {
            $tcp = $checks.Tcp
            if (-not $tcp.Contains('TimeoutMilliseconds') -or -not (Test-InfraPulseNumber -Value $tcp.TimeoutMilliseconds -Minimum 100 -Maximum 60000)) {
                [void]$errors.Add('Checks.Tcp.TimeoutMilliseconds must be between 100 and 60000.')
            }
            $index = 0
            foreach ($endpoint in @($tcp.Endpoints)) {
                if (-not ($endpoint -is [System.Collections.IDictionary])) {
                    [void]$errors.Add("Checks.Tcp.Endpoints[$index] must be a hashtable.")
                }
                else {
                    if (-not $endpoint.Contains('Host') -or [string]::IsNullOrWhiteSpace([string]$endpoint.Host)) {
                        [void]$errors.Add("Checks.Tcp.Endpoints[$index].Host is required.")
                    }
                    if (-not $endpoint.Contains('Port') -or -not (Test-InfraPulseNumber -Value $endpoint.Port -Minimum 1 -Maximum 65535)) {
                        [void]$errors.Add("Checks.Tcp.Endpoints[$index].Port must be between 1 and 65535.")
                    }
                    if ($endpoint.Contains('TimeoutMilliseconds') -and -not (Test-InfraPulseNumber -Value $endpoint.TimeoutMilliseconds -Minimum 100 -Maximum 60000)) {
                        [void]$errors.Add("Checks.Tcp.Endpoints[$index].TimeoutMilliseconds must be between 100 and 60000.")
                    }
                }
                $index++
            }
        }

        if ($checks.Contains('TimeSync')) {
            $timeSync = $checks.TimeSync
            if (-not $timeSync.Contains('TimeoutMilliseconds') -or -not (Test-InfraPulseNumber -Value $timeSync.TimeoutMilliseconds -Minimum 100 -Maximum 60000)) {
                [void]$errors.Add('Checks.TimeSync.TimeoutMilliseconds must be between 100 and 60000.')
            }
            foreach ($name in @('WarningOffsetSeconds', 'CriticalOffsetSeconds')) {
                if (-not $timeSync.Contains($name) -or -not (Test-InfraPulseNumber -Value $timeSync[$name] -Minimum 0)) {
                    [void]$errors.Add("Checks.TimeSync.$name must be zero or greater.")
                }
            }
            if (
                (Test-InfraPulseNumber -Value $timeSync.WarningOffsetSeconds) -and
                (Test-InfraPulseNumber -Value $timeSync.CriticalOffsetSeconds) -and
                [double]$timeSync.CriticalOffsetSeconds -lt [double]$timeSync.WarningOffsetSeconds
            ) {
                [void]$errors.Add('Checks.TimeSync.CriticalOffsetSeconds must be greater than or equal to WarningOffsetSeconds.')
            }
            foreach ($server in @($timeSync.Servers)) {
                if ([string]::IsNullOrWhiteSpace([string]$server)) {
                    [void]$errors.Add('Checks.TimeSync.Servers cannot contain an empty value.')
                }
            }
        }
    }

    [pscustomobject]@{
        IsValid  = $errors.Count -eq 0
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}
