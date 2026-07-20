function Invoke-InfraPulseCertificateCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $storePaths = @($Settings.StorePaths)
    if ($storePaths.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Certificates' -Category 'Security' -ComputerName $Context.ComputerName -Target 'Certificate stores' -Message 'No certificate stores are configured.' -Recommendation 'Add LocalMachine certificate-provider paths under Checks.Certificates.StorePaths.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        param($CheckSettings)

        if ($env:OS -ne 'Windows_NT') {
            throw 'The Certificates check requires a Windows target.'
        }

        foreach ($storePath in @($CheckSettings.StorePaths)) {
            if (-not (Test-Path -LiteralPath $storePath)) {
                [pscustomobject]@{
                    RecordType = 'Store'
                    StorePath  = [string]$storePath
                    Exists     = $false
                }
                continue
            }

            [pscustomobject]@{
                RecordType = 'Store'
                StorePath  = [string]$storePath
                Exists     = $true
            }

            foreach ($certificate in @(Get-ChildItem -LiteralPath $storePath -ErrorAction Stop)) {
                if ($certificate -isnot [System.Security.Cryptography.X509Certificates.X509Certificate2]) {
                    continue
                }

                if ([bool]$CheckSettings.RequirePrivateKey -and -not $certificate.HasPrivateKey) {
                    continue
                }

                if ([string]$certificate.Thumbprint -in @($CheckSettings.ThumbprintExclude)) {
                    continue
                }

                $excluded = $false
                foreach ($pattern in @($CheckSettings.SubjectExcludePatterns)) {
                    if ([string]$certificate.Subject -like [string]$pattern) {
                        $excluded = $true
                        break
                    }
                }
                if ($excluded) {
                    continue
                }

                foreach ($pattern in @($CheckSettings.IssuerExcludePatterns)) {
                    if ([string]$certificate.Issuer -like [string]$pattern) {
                        $excluded = $true
                        break
                    }
                }
                if ($excluded) {
                    continue
                }

                $totalLifetimeDays = (([datetime]$certificate.NotAfter) - ([datetime]$certificate.NotBefore)).TotalDays
                if ($totalLifetimeDays -lt [double]$CheckSettings.MinTotalLifetimeDays) {
                    continue
                }

                [pscustomobject]@{
                    RecordType   = 'Certificate'
                    StorePath    = [string]$storePath
                    Subject      = [string]$certificate.Subject
                    Issuer       = [string]$certificate.Issuer
                    Thumbprint   = [string]$certificate.Thumbprint
                    NotBefore    = [datetime]$certificate.NotBefore
                    NotAfter     = [datetime]$certificate.NotAfter
                    DaysRemaining = [math]::Round((([datetime]$certificate.NotAfter) - (Get-Date)).TotalDays, 2)
                    HasPrivateKey = [bool]$certificate.HasPrivateKey
                    SerialNumber  = [string]$certificate.SerialNumber
                }
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @($Settings))
    $stopwatch.Stop()

    $stores = @($raw | Where-Object { $_.RecordType -eq 'Store' })
    $certificates = @($raw | Where-Object { $_.RecordType -eq 'Certificate' })
    $existingStores = @($stores | Where-Object { $_.Exists }).Count
    $missingStores = @($stores | Where-Object { -not $_.Exists } | ForEach-Object { $_.StorePath })

    if ($existingStores -eq 0) {
        return New-InfraPulseResult -Status 'Unknown' -CheckName 'Certificates' -Category 'Security' -ComputerName $Context.ComputerName -Target 'Certificate stores' -Message 'None of the configured certificate stores exist on the target.' -Recommendation 'Review Checks.Certificates.StorePaths for the target role.' -Evidence ([ordered]@{ MissingStores = $missingStores }) -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $results = @()
    $healthyCertificates = @()

    foreach ($missingStore in $missingStores) {
        $results += New-InfraPulseResult -Status 'Unknown' -CheckName 'Certificates' -Category 'Security' -ComputerName $Context.ComputerName -Target ([string]$missingStore) -Message "Configured certificate store '$missingStore' does not exist on the target." -ObservedValue 'Missing' -Recommendation 'Remove the store from Checks.Certificates.StorePaths or confirm the target role provisions it.' -Evidence ([ordered]@{ StorePath = [string]$missingStore; Exists = $false }) -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / [math]::Max($storePaths.Count, 1))
    }

    foreach ($certificate in $certificates) {
        $daysRemaining = [double]$certificate.DaysRemaining
        if ($daysRemaining -lt 0) {
            $status = 'Critical'
            $message = "Certificate expired $([math]::Abs([math]::Round($daysRemaining, 0))) day(s) ago on $(([datetime]$certificate.NotAfter).ToString('yyyy-MM-dd'))."
            $recommendation = 'Replace or remove the expired certificate after confirming its bindings and dependent services.'
        }
        elseif ($daysRemaining -le [double]$Settings.CriticalDays) {
            $status = 'Critical'
            $message = "Certificate expires in $([math]::Round($daysRemaining, 0)) day(s) on $(([datetime]$certificate.NotAfter).ToString('yyyy-MM-dd'))."
            $recommendation = 'Renew and deploy the certificate immediately, then validate all bindings and trust chains.'
        }
        elseif ($daysRemaining -le [double]$Settings.WarningDays) {
            $status = 'Warning'
            $message = "Certificate expires in $([math]::Round($daysRemaining, 0)) day(s) on $(([datetime]$certificate.NotAfter).ToString('yyyy-MM-dd'))."
            $recommendation = 'Begin the renewal process and identify every service or endpoint using this certificate.'
        }
        else {
            $healthyCertificates += $certificate
            continue
        }

        $thumbprint = [string]$certificate.Thumbprint
        $shortThumbprint = if ($thumbprint.Length -gt 12) { $thumbprint.Substring($thumbprint.Length - 12) } else { $thumbprint }
        $target = if ([string]::IsNullOrWhiteSpace([string]$certificate.Subject)) { $shortThumbprint } else { '{0} [{1}]' -f [string]$certificate.Subject, $shortThumbprint }
        $evidence = [ordered]@{
            Subject       = [string]$certificate.Subject
            Issuer        = [string]$certificate.Issuer
            Thumbprint    = $thumbprint
            SerialNumber  = [string]$certificate.SerialNumber
            StorePath     = [string]$certificate.StorePath
            NotBefore     = [datetime]$certificate.NotBefore
            NotAfter      = [datetime]$certificate.NotAfter
            DaysRemaining = $daysRemaining
            HasPrivateKey = [bool]$certificate.HasPrivateKey
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'Certificates' -Category 'Security' -ComputerName $Context.ComputerName -Target $target -Message $message -ObservedValue ("{0:N2} days" -f $daysRemaining) -WarningThreshold ("<= {0} days" -f $Settings.WarningDays) -CriticalThreshold ("<= {0} days or expired" -f $Settings.CriticalDays) -Recommendation $recommendation -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / [math]::Max($certificates.Count, 1))
    }

    $summaryMessage = if ($certificates.Count -eq 0) {
        'No certificates matched the configured filters in the available stores.'
    }
    else {
        "$($healthyCertificates.Count) of $($certificates.Count) certificate(s) are valid beyond the warning threshold."
    }

    $summaryEvidence = [ordered]@{
        TotalCertificates   = $certificates.Count
        HealthyCertificates = $healthyCertificates.Count
        ExistingStores      = @($stores | Where-Object { $_.Exists } | ForEach-Object { $_.StorePath })
        MissingStores       = $missingStores
    }
    $results += New-InfraPulseResult -Status 'Healthy' -CheckName 'Certificates' -Category 'Security' -ComputerName $Context.ComputerName -Target 'Certificate inventory' -Message $summaryMessage -ObservedValue $healthyCertificates.Count -WarningThreshold ("Expiry <= {0} days" -f $Settings.WarningDays) -CriticalThreshold ("Expiry <= {0} days" -f $Settings.CriticalDays) -Evidence $summaryEvidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds

    return $results
}
