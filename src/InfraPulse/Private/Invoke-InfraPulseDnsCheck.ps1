function Invoke-InfraPulseDnsCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $targets = @($Settings.Targets)
    if ($targets.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Dns' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target 'DNS targets' -Message 'No DNS targets are configured.' -Recommendation 'Add required names under Checks.Dns.Targets to validate name resolution from the target host.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        param($CheckSettings)

        foreach ($configuredTarget in @($CheckSettings.Targets)) {
            if ($configuredTarget -is [string]) {
                $name = [string]$configuredTarget
                $queryType = [string]$CheckSettings.QueryType
                $server = [string]$CheckSettings.Server
            }
            else {
                $name = [string]$configuredTarget.Name
                $queryType = if ($configuredTarget.Contains('Type')) { [string]$configuredTarget.Type } else { [string]$CheckSettings.QueryType }
                $server = if ($configuredTarget.Contains('Server')) { [string]$configuredTarget.Server } else { [string]$CheckSettings.Server }
            }

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $answers = @()
                if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
                    $parameters = @{
                        Name        = $name
                        Type        = $queryType
                        DnsOnly     = $true
                        ErrorAction = 'Stop'
                    }
                    if (-not [string]::IsNullOrWhiteSpace($server)) {
                        $parameters.Server = $server
                    }
                    $records = @(Resolve-DnsName @parameters)
                    foreach ($record in $records) {
                        if ($record.IPAddress) {
                            $answers += [string]$record.IPAddress
                        }
                        elseif ($record.NameHost) {
                            $answers += [string]$record.NameHost
                        }
                        elseif ($record.NameExchange) {
                            $answers += [string]$record.NameExchange
                        }
                        elseif ($record.NameTarget) {
                            $answers += [string]$record.NameTarget
                        }
                        elseif ($record.Strings) {
                            $answers += (@($record.Strings) -join ' ')
                        }
                        elseif ($record.PrimaryServer) {
                            $answers += [string]$record.PrimaryServer
                        }
                    }
                }
                else {
                    if (-not [string]::IsNullOrWhiteSpace($server)) {
                        throw 'A custom DNS server requires Resolve-DnsName on the target.'
                    }
                    if ($queryType -notin @('A', 'AAAA')) {
                        throw "Query type '$queryType' requires Resolve-DnsName on the target."
                    }
                    $addressFamily = if ($queryType -eq 'AAAA') {
                        [System.Net.Sockets.AddressFamily]::InterNetworkV6
                    }
                    else {
                        [System.Net.Sockets.AddressFamily]::InterNetwork
                    }
                    $addresses = [System.Net.Dns]::GetHostAddresses($name) |
                        Where-Object { $_.AddressFamily -eq $addressFamily }
                    $answers = @($addresses | ForEach-Object { $_.IPAddressToString })
                }
                $timer.Stop()

                [pscustomobject]@{
                    Name        = $name
                    QueryType   = $queryType
                    Server      = $server
                    Success     = $answers.Count -gt 0
                    Answers     = @($answers | Select-Object -Unique)
                    DurationMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    FailureKind = $null
                    Error       = $null
                }
            }
            catch {
                $timer.Stop()
                $errorMessage = $_.Exception.Message
                $failureKind = if ($errorMessage -like '*requires Resolve-DnsName*') { 'UnsupportedQuery' } else { 'ResolutionFailure' }
                [pscustomobject]@{
                    Name        = $name
                    QueryType   = $queryType
                    Server      = $server
                    Success     = $false
                    Answers     = @()
                    DurationMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    FailureKind = $failureKind
                    Error       = $errorMessage
                }
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $stopwatch.Stop()

    $results = @()
    foreach ($query in $raw) {
        $failureKind = if ($null -ne $query.PSObject.Properties['FailureKind']) { [string]$query.FailureKind } else { '' }
        if ([bool]$query.Success) {
            $status = 'Healthy'
            $message = "Resolved $($query.Name) [$($query.QueryType)] to $(@($query.Answers) -join ', ') in $($query.DurationMs) ms."
            $recommendation = ''
        }
        elseif ($failureKind -eq 'UnsupportedQuery') {
            $status = 'Unknown'
            $message = "DNS query $($query.Name) [$($query.QueryType)] is not supported by the target runtime."
            $recommendation = 'Run the check on a target that provides Resolve-DnsName, or use A/AAAA resolution without a custom DNS server.'
        }
        else {
            $status = 'Critical'
            $message = "DNS resolution failed for $($query.Name) [$($query.QueryType)]."
            $recommendation = 'Validate DNS client configuration, resolver reachability, suffix/search behavior, and the authoritative record.'
        }

        $evidence = [ordered]@{
            Name        = [string]$query.Name
            QueryType   = [string]$query.QueryType
            Server      = [string]$query.Server
            Answers     = @($query.Answers)
            DurationMs  = [double]$query.DurationMs
            FailureKind = $failureKind
            Error       = [string]$query.Error
        }

        $criticalThreshold = if ($status -eq 'Unknown') { $null } else { 'Resolution failure' }
        $results += New-InfraPulseResult -Status $status -CheckName 'Dns' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target ([string]$query.Name) -Message $message -ObservedValue (@($query.Answers) -join ', ') -WarningThreshold $null -CriticalThreshold $criticalThreshold -Recommendation $recommendation -Evidence $evidence -DurationMs ([double]$query.DurationMs) -ErrorMessage ([string]$query.Error)
    }

    return $results
}
