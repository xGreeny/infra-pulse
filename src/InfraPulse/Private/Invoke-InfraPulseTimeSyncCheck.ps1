function Invoke-InfraPulseTimeSyncCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $servers = @($Settings.Servers)
    if ($servers.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'TimeSync' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target 'NTP servers' -Message 'No NTP servers are configured.' -Recommendation 'Add NTP server names under Checks.TimeSync.Servers.'
    }

    $scriptBlock = {
        param($CheckSettings)

        function Write-NtpTimestamp {
            param(
                [byte[]]$Buffer,
                [int]$Offset,
                [datetime]$Timestamp
            )

            $epoch = [datetime]::SpecifyKind([datetime]'1900-01-01 00:00:00', [DateTimeKind]::Utc)
            $totalSeconds = ($Timestamp.ToUniversalTime() - $epoch).TotalSeconds
            $seconds = [uint32][math]::Floor($totalSeconds)
            $fractionValue = [math]::Floor(($totalSeconds - [math]::Floor($totalSeconds)) * 4294967296.0)
            if ($fractionValue -gt [uint32]::MaxValue) {
                $fractionValue = [uint32]::MaxValue
            }
            $fraction = [uint32]$fractionValue

            $secondsBytes = [BitConverter]::GetBytes($seconds)
            $fractionBytes = [BitConverter]::GetBytes($fraction)
            if ([BitConverter]::IsLittleEndian) {
                [Array]::Reverse($secondsBytes)
                [Array]::Reverse($fractionBytes)
            }
            [Array]::Copy($secondsBytes, 0, $Buffer, $Offset, 4)
            [Array]::Copy($fractionBytes, 0, $Buffer, $Offset + 4, 4)
        }

        function Read-NtpTimestamp {
            param(
                [byte[]]$Buffer,
                [int]$Offset
            )

            $secondsBytes = New-Object byte[] 4
            $fractionBytes = New-Object byte[] 4
            [Array]::Copy($Buffer, $Offset, $secondsBytes, 0, 4)
            [Array]::Copy($Buffer, $Offset + 4, $fractionBytes, 0, 4)
            if ([BitConverter]::IsLittleEndian) {
                [Array]::Reverse($secondsBytes)
                [Array]::Reverse($fractionBytes)
            }

            $seconds = [BitConverter]::ToUInt32($secondsBytes, 0)
            $fraction = [BitConverter]::ToUInt32($fractionBytes, 0)
            $epoch = [datetime]::SpecifyKind([datetime]'1900-01-01 00:00:00', [DateTimeKind]::Utc)
            return $epoch.AddSeconds([double]$seconds + ([double]$fraction / 4294967296.0))
        }

        foreach ($server in @($CheckSettings.Servers)) {
            $serverName = [string]$server
            $udpClient = $null
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $addresses = @(
                    [System.Net.Dns]::GetHostAddresses($serverName) |
                        Where-Object {
                            $_.AddressFamily -in @(
                                [System.Net.Sockets.AddressFamily]::InterNetwork,
                                [System.Net.Sockets.AddressFamily]::InterNetworkV6
                            )
                        }
                )
                $address = $addresses |
                    Sort-Object -Property @{ Expression = { if ($_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 0 } else { 1 } } } |
                    Select-Object -First 1
                if ($null -eq $address) {
                    throw 'No IPv4 or IPv6 address was returned for the NTP server.'
                }

                $request = New-Object byte[] 48
                $request[0] = 0x23
                $t1 = [DateTime]::UtcNow
                Write-NtpTimestamp -Buffer $request -Offset 40 -Timestamp $t1

                $udpClient = New-Object System.Net.Sockets.UdpClient -ArgumentList $address.AddressFamily
                $udpClient.Client.ReceiveTimeout = [int]$CheckSettings.TimeoutMilliseconds
                $udpClient.Connect($address, 123)
                $null = $udpClient.Send($request, $request.Length)

                $anyAddress = if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    [System.Net.IPAddress]::IPv6Any
                }
                else {
                    [System.Net.IPAddress]::Any
                }
                $remoteEndpoint = New-Object System.Net.IPEndPoint -ArgumentList ($anyAddress, 0)
                $response = $udpClient.Receive([ref]$remoteEndpoint)
                $t4 = [DateTime]::UtcNow
                $timer.Stop()

                if ($response.Length -lt 48) {
                    throw "NTP response contained only $($response.Length) bytes."
                }

                for ($index = 0; $index -lt 8; $index++) {
                    if ($response[24 + $index] -ne $request[40 + $index]) {
                        throw 'The NTP response originate timestamp does not match the request.'
                    }
                }

                $leapIndicator = ($response[0] -shr 6) -band 0x03
                $version = ($response[0] -shr 3) -band 0x07
                $mode = $response[0] -band 0x07
                $stratum = [int]$response[1]
                if ($leapIndicator -eq 3) {
                    throw 'The NTP server reports an unsynchronized clock.'
                }
                if ($version -lt 3 -or $version -gt 4) {
                    throw "The NTP response used unsupported protocol version '$version'."
                }
                if ($mode -ne 4) {
                    throw "The NTP response used mode '$mode' instead of server mode 4."
                }
                if ($stratum -eq 0) {
                    throw 'The NTP server returned a kiss-of-death or invalid stratum response.'
                }
                if ($stratum -gt 15) {
                    throw "The NTP server returned invalid or unsynchronized stratum '$stratum'."
                }

                $t2 = Read-NtpTimestamp -Buffer $response -Offset 32
                $t3 = Read-NtpTimestamp -Buffer $response -Offset 40
                $offsetSeconds = ((($t2 - $t1).TotalSeconds) + (($t3 - $t4).TotalSeconds)) / 2.0
                $roundTripMs = ((($t4 - $t1).TotalSeconds - ($t3 - $t2).TotalSeconds) * 1000.0)
                if ($roundTripMs -lt 0) {
                    $roundTripMs = 0
                }

                [pscustomobject]@{
                    Server               = $serverName
                    Address              = $address.IPAddressToString
                    Success              = $true
                    OffsetSeconds        = [math]::Round($offsetSeconds, 6)
                    AbsoluteOffsetSeconds = [math]::Round([math]::Abs($offsetSeconds), 6)
                    RoundTripMilliseconds = [math]::Round($roundTripMs, 2)
                    Stratum              = $stratum
                    Version              = $version
                    Mode                 = $mode
                    DurationMs           = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    Error                = $null
                }
            }
            catch {
                $timer.Stop()
                [pscustomobject]@{
                    Server               = $serverName
                    Address              = $null
                    Success              = $false
                    OffsetSeconds        = $null
                    AbsoluteOffsetSeconds = $null
                    RoundTripMilliseconds = $null
                    Stratum              = $null
                    Version              = $null
                    Mode                 = $null
                    DurationMs           = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    Error                = $_.Exception.Message
                }
            }
            finally {
                if ($null -ne $udpClient) {
                    $udpClient.Close()
                }
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $results = @()

    foreach ($sample in $raw) {
        if (-not [bool]$sample.Success) {
            $status = 'Unknown'
            $message = "NTP query to $($sample.Server) failed."
            $recommendation = 'Validate DNS, UDP/123 reachability, NTP policy, and the configured time source.'
            $observed = $null
        }
        elseif ([double]$sample.AbsoluteOffsetSeconds -ge [double]$Settings.CriticalOffsetSeconds) {
            $status = 'Critical'
            $message = "Clock offset against $($sample.Server) is $($sample.OffsetSeconds) seconds."
            $recommendation = 'Correct the time hierarchy and synchronization state immediately; large offsets can break authentication and distributed workloads.'
            $observed = [double]$sample.OffsetSeconds
        }
        elseif ([double]$sample.AbsoluteOffsetSeconds -ge [double]$Settings.WarningOffsetSeconds) {
            $status = 'Warning'
            $message = "Clock offset against $($sample.Server) is $($sample.OffsetSeconds) seconds."
            $recommendation = 'Review time-source selection, synchronization health, and network latency before the offset becomes service-impacting.'
            $observed = [double]$sample.OffsetSeconds
        }
        else {
            $status = 'Healthy'
            $message = "Clock offset against $($sample.Server) is $($sample.OffsetSeconds) seconds."
            $recommendation = ''
            $observed = [double]$sample.OffsetSeconds
        }

        $evidence = [ordered]@{
            Server                = [string]$sample.Server
            Address               = [string]$sample.Address
            OffsetSeconds         = $sample.OffsetSeconds
            AbsoluteOffsetSeconds = $sample.AbsoluteOffsetSeconds
            RoundTripMilliseconds = $sample.RoundTripMilliseconds
            Stratum               = $sample.Stratum
            NtpVersion            = $sample.Version
            Mode                  = $sample.Mode
            DurationMs            = [double]$sample.DurationMs
            Error                 = [string]$sample.Error
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'TimeSync' -Category 'Connectivity' -ComputerName $Context.ComputerName -Target ([string]$sample.Server) -Message $message -ObservedValue $observed -WarningThreshold (">= {0} seconds absolute offset" -f $Settings.WarningOffsetSeconds) -CriticalThreshold (">= {0} seconds absolute offset" -f $Settings.CriticalOffsetSeconds) -Recommendation $recommendation -Evidence $evidence -DurationMs ([double]$sample.DurationMs) -ErrorMessage ([string]$sample.Error)
    }

    return $results
}
