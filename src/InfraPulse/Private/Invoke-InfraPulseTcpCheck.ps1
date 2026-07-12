function Invoke-InfraPulseTcpCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $endpoints = @($Settings.Endpoints)
    if ($endpoints.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Tcp' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target 'TCP endpoints' -Message 'No TCP endpoints are configured.' -Recommendation 'Add required host and port pairs under Checks.Tcp.Endpoints.'
    }

    $scriptBlock = {
        param($CheckSettings)

        foreach ($endpoint in @($CheckSettings.Endpoints)) {
            $hostName = [string]$endpoint.Host
            $port = [int]$endpoint.Port
            $displayName = if ($endpoint.Contains('Name') -and -not [string]::IsNullOrWhiteSpace([string]$endpoint.Name)) { [string]$endpoint.Name } else { "$hostName`:$port" }
            $timeout = if ($endpoint.Contains('TimeoutMilliseconds')) { [int]$endpoint.TimeoutMilliseconds } else { [int]$CheckSettings.TimeoutMilliseconds }
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $client = New-Object System.Net.Sockets.TcpClient
            $waitHandle = $null

            try {
                $asyncResult = $client.BeginConnect($hostName, $port, $null, $null)
                $waitHandle = $asyncResult.AsyncWaitHandle
                if (-not $waitHandle.WaitOne($timeout, $false)) {
                    throw "Connection timed out after $timeout ms."
                }
                $client.EndConnect($asyncResult)
                $timer.Stop()

                [pscustomobject]@{
                    Name       = $displayName
                    Host       = $hostName
                    Port       = $port
                    Success    = $client.Connected
                    DurationMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    TimeoutMs  = $timeout
                    Error      = $null
                }
            }
            catch {
                $timer.Stop()
                [pscustomobject]@{
                    Name       = $displayName
                    Host       = $hostName
                    Port       = $port
                    Success    = $false
                    DurationMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    TimeoutMs  = $timeout
                    Error      = $_.Exception.Message
                }
            }
            finally {
                if ($null -ne $waitHandle) {
                    $waitHandle.Close()
                }
                $client.Close()
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $results = @()

    foreach ($endpoint in $raw) {
        if ([bool]$endpoint.Success) {
            $status = 'Healthy'
            $message = "Connected to $($endpoint.Host):$($endpoint.Port) in $($endpoint.DurationMs) ms."
            $recommendation = ''
        }
        else {
            $status = 'Critical'
            $message = "TCP connection to $($endpoint.Host):$($endpoint.Port) failed after $($endpoint.DurationMs) ms."
            $recommendation = 'Validate routing, firewall policy, name resolution, listener state, and service dependencies from the target host.'
        }

        $evidence = [ordered]@{
            Name       = [string]$endpoint.Name
            Host       = [string]$endpoint.Host
            Port       = [int]$endpoint.Port
            DurationMs = [double]$endpoint.DurationMs
            TimeoutMs  = [int]$endpoint.TimeoutMs
            Error      = [string]$endpoint.Error
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'Tcp' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target ([string]$endpoint.Name) -Message $message -ObservedValue ([bool]$endpoint.Success) -WarningThreshold $null -CriticalThreshold 'Connection failure' -Recommendation $recommendation -Evidence $evidence -DurationMs ([double]$endpoint.DurationMs) -ErrorMessage ([string]$endpoint.Error)
    }

    return $results
}
