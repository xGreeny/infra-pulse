function Invoke-InfraPulseTlsCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $endpoints = @($Settings.Endpoints)
    if ($endpoints.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Tls' -Category 'Security' -ComputerName $Context.ComputerName -Target 'TLS endpoints' -Message 'No TLS endpoints are configured.' -Recommendation 'Add host entries under Checks.Tls.Endpoints to validate TLS handshakes, certificate identity, and expiry.'
    }

    $scriptBlock = {
        param($CheckSettings)

        foreach ($endpoint in @($CheckSettings.Endpoints)) {
            $hostName = [string]$endpoint.Host
            $port = if ($endpoint.Contains('Port')) { [int]$endpoint.Port } else { 443 }
            $sni = if ($endpoint.Contains('Sni') -and -not [string]::IsNullOrWhiteSpace([string]$endpoint.Sni)) { [string]$endpoint.Sni } else { $hostName }
            $displayName = if ($endpoint.Contains('Name') -and -not [string]::IsNullOrWhiteSpace([string]$endpoint.Name)) { [string]$endpoint.Name } else { "$hostName`:$port" }
            $timeout = if ($endpoint.Contains('TimeoutMilliseconds')) { [int]$endpoint.TimeoutMilliseconds } else { [int]$CheckSettings.TimeoutMilliseconds }

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $client = New-Object System.Net.Sockets.TcpClient
            $waitHandle = $null
            $sslStream = $null

            # The validation callback runs synchronously on this thread during
            # AuthenticateAsClient; script scope carries its findings out.
            $script:InfraPulseTlsProbe = @{
                PolicyErrors = $null
                ChainStatus  = @()
            }

            try {
                $asyncResult = $client.BeginConnect($hostName, $port, $null, $null)
                $waitHandle = $asyncResult.AsyncWaitHandle
                if (-not $waitHandle.WaitOne($timeout, $false)) {
                    throw "Connection timed out after $timeout ms."
                }
                $client.EndConnect($asyncResult)
                $client.ReceiveTimeout = $timeout
                $client.SendTimeout = $timeout

                $validationCallback = [System.Net.Security.RemoteCertificateValidationCallback]{
                    param($senderObject, $callbackCertificate, $callbackChain, $sslPolicyErrors)
                    $null = $senderObject, $callbackCertificate
                    $script:InfraPulseTlsProbe.PolicyErrors = $sslPolicyErrors
                    if ($null -ne $callbackChain) {
                        $script:InfraPulseTlsProbe.ChainStatus = @(
                            foreach ($chainStatus in @($callbackChain.ChainStatus)) {
                                '{0}: {1}' -f $chainStatus.Status, ([string]$chainStatus.StatusInformation).Trim()
                            }
                        )
                    }
                    return $true
                }

                $sslStream = New-Object System.Net.Security.SslStream($client.GetStream(), $false, $validationCallback)
                $sslStream.AuthenticateAsClient($sni)
                $timer.Stop()

                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
                $policyErrors = $script:InfraPulseTlsProbe.PolicyErrors
                $nameMatch = $true
                $chainTrusted = $true
                if ($null -ne $policyErrors) {
                    $nameMatch = (([int]$policyErrors) -band [int][System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) -eq 0
                    $chainTrusted = (([int]$policyErrors) -band [int][System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors) -eq 0
                }

                [pscustomobject]@{
                    Name               = $displayName
                    Host               = $hostName
                    Port               = $port
                    Sni                = $sni
                    HandshakeSucceeded = $true
                    Protocol           = $sslStream.SslProtocol.ToString()
                    Subject            = [string]$certificate.Subject
                    Issuer             = [string]$certificate.Issuer
                    Thumbprint         = [string]$certificate.Thumbprint
                    SerialNumber       = [string]$certificate.SerialNumber
                    NotBefore          = [datetime]$certificate.NotBefore
                    NotAfter           = [datetime]$certificate.NotAfter
                    DaysRemaining      = [math]::Round((([datetime]$certificate.NotAfter) - (Get-Date)).TotalDays, 2)
                    NameMatch          = $nameMatch
                    ChainTrusted       = $chainTrusted
                    ChainStatus        = @($script:InfraPulseTlsProbe.ChainStatus)
                    PolicyErrors       = [string]$policyErrors
                    DurationMs         = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    TimeoutMs          = $timeout
                    Error              = $null
                }
            }
            catch {
                $timer.Stop()
                [pscustomobject]@{
                    Name               = $displayName
                    Host               = $hostName
                    Port               = $port
                    Sni                = $sni
                    HandshakeSucceeded = $false
                    Protocol           = $null
                    Subject            = $null
                    Issuer             = $null
                    Thumbprint         = $null
                    SerialNumber       = $null
                    NotBefore          = $null
                    NotAfter           = $null
                    DaysRemaining      = $null
                    NameMatch          = $false
                    ChainTrusted       = $false
                    ChainStatus        = @($script:InfraPulseTlsProbe.ChainStatus)
                    PolicyErrors       = [string]$script:InfraPulseTlsProbe.PolicyErrors
                    DurationMs         = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    TimeoutMs          = $timeout
                    Error              = $_.Exception.Message
                }
            }
            finally {
                if ($null -ne $sslStream) {
                    $sslStream.Dispose()
                }
                if ($null -ne $waitHandle) {
                    $waitHandle.Close()
                }
                $client.Close()
                Remove-Variable -Name InfraPulseTlsProbe -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $results = @()

    foreach ($endpoint in $raw) {
        $target = [string]$endpoint.Name
        $endpointLabel = '{0}:{1}' -f [string]$endpoint.Host, [int]$endpoint.Port

        if (-not [bool]$endpoint.HandshakeSucceeded) {
            $results += New-InfraPulseResult -Status 'Critical' -CheckName 'Tls' -Category 'Security' -ComputerName $Context.ComputerName -Target $target -Message "TLS handshake with $endpointLabel failed after $($endpoint.DurationMs) ms." -ObservedValue 'Handshake failed' -WarningThreshold ("Expiry <= {0} days" -f $Settings.WarningDays) -CriticalThreshold 'Handshake, identity, or trust failure' -Recommendation 'Validate listener state, TLS protocol support, firewall policy, and name resolution from the target host.' -Evidence (New-InfraPulseTlsEvidence -Endpoint $endpoint) -DurationMs ([double]$endpoint.DurationMs) -ErrorMessage ([string]$endpoint.Error)
            continue
        }

        $daysRemaining = [double]$endpoint.DaysRemaining
        $criticalReasons = @()
        if ($daysRemaining -lt 0) {
            $criticalReasons += "certificate expired $([math]::Abs([math]::Round($daysRemaining, 0))) day(s) ago on $(([datetime]$endpoint.NotAfter).ToString('yyyy-MM-dd'))"
        }
        if ([bool]$Settings.RequireNameMatch -and -not [bool]$endpoint.NameMatch) {
            $criticalReasons += "certificate identity does not match requested name '$($endpoint.Sni)'"
        }
        if ([bool]$Settings.RequireTrustedChain -and -not [bool]$endpoint.ChainTrusted) {
            $criticalReasons += 'certificate chain is not trusted on the evaluated host'
        }
        if ($daysRemaining -ge 0 -and $daysRemaining -le [double]$Settings.CriticalDays) {
            $criticalReasons += "certificate expires in $([math]::Round($daysRemaining, 0)) day(s) on $(([datetime]$endpoint.NotAfter).ToString('yyyy-MM-dd'))"
        }

        if ($criticalReasons.Count -gt 0) {
            $status = 'Critical'
            $message = 'TLS validation for {0} failed: {1}.' -f $endpointLabel, (($criticalReasons -join '; '))
            $recommendation = 'Renew or redeploy the certificate, correct the served identity and chain, and re-validate every dependent endpoint.'
        }
        elseif ($daysRemaining -le [double]$Settings.WarningDays) {
            $status = 'Warning'
            $message = "Certificate for $endpointLabel expires in $([math]::Round($daysRemaining, 0)) day(s) on $(([datetime]$endpoint.NotAfter).ToString('yyyy-MM-dd'))."
            $recommendation = 'Begin the renewal process and identify every service or endpoint using this certificate.'
        }
        else {
            $status = 'Healthy'
            $message = "TLS handshake with $endpointLabel succeeded using $($endpoint.Protocol); certificate is valid for $([math]::Round($daysRemaining, 0)) more day(s)."
            $recommendation = ''
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'Tls' -Category 'Security' -ComputerName $Context.ComputerName -Target $target -Message $message -ObservedValue ("{0:N2} days" -f $daysRemaining) -WarningThreshold ("Expiry <= {0} days" -f $Settings.WarningDays) -CriticalThreshold ("Expiry <= {0} days, expired, or handshake/identity/trust failure" -f $Settings.CriticalDays) -Recommendation $recommendation -Evidence (New-InfraPulseTlsEvidence -Endpoint $endpoint) -DurationMs ([double]$endpoint.DurationMs) -ErrorMessage ([string]$endpoint.Error)
    }

    return $results
}

function New-InfraPulseTlsEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Endpoint
    )

    [ordered]@{
        Name               = [string]$Endpoint.Name
        Host               = [string]$Endpoint.Host
        Port               = [int]$Endpoint.Port
        Sni                = [string]$Endpoint.Sni
        HandshakeSucceeded = [bool]$Endpoint.HandshakeSucceeded
        Protocol           = [string]$Endpoint.Protocol
        Subject            = [string]$Endpoint.Subject
        Issuer             = [string]$Endpoint.Issuer
        Thumbprint         = [string]$Endpoint.Thumbprint
        SerialNumber       = [string]$Endpoint.SerialNumber
        NotBefore          = $Endpoint.NotBefore
        NotAfter           = $Endpoint.NotAfter
        DaysRemaining      = $Endpoint.DaysRemaining
        NameMatch          = [bool]$Endpoint.NameMatch
        ChainTrusted       = [bool]$Endpoint.ChainTrusted
        ChainStatus        = @($Endpoint.ChainStatus)
        PolicyErrors       = [string]$Endpoint.PolicyErrors
        HandshakeMs        = [double]$Endpoint.DurationMs
        TimeoutMs          = [int]$Endpoint.TimeoutMs
        Error              = [string]$Endpoint.Error
    }
}
