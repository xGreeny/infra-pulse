function Get-InfraPulseCheckCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            Name            = 'Disk'
            Category        = 'Capacity'
            FunctionName    = 'Invoke-InfraPulseDiskCheck'
            RequiresWindows = $true
            Description     = 'Evaluates fixed-disk free space using percentage and absolute thresholds.'
        }
        [pscustomobject]@{
            Name            = 'Memory'
            Category        = 'Capacity'
            FunctionName    = 'Invoke-InfraPulseMemoryCheck'
            RequiresWindows = $true
            Description     = 'Evaluates currently available physical memory.'
        }
        [pscustomobject]@{
            Name            = 'Uptime'
            Category        = 'Lifecycle'
            FunctionName    = 'Invoke-InfraPulseUptimeCheck'
            RequiresWindows = $true
            Description     = 'Flags hosts that have exceeded configured uptime thresholds.'
        }
        [pscustomobject]@{
            Name            = 'PendingReboot'
            Category        = 'Lifecycle'
            FunctionName    = 'Invoke-InfraPulsePendingRebootCheck'
            RequiresWindows = $true
            Description     = 'Checks servicing, Windows Update, file rename, computer rename, and Configuration Manager reboot indicators.'
        }
        [pscustomobject]@{
            Name            = 'PatchAge'
            Category        = 'Lifecycle'
            FunctionName    = 'Invoke-InfraPulsePatchAgeCheck'
            RequiresWindows = $true
            Description     = 'Evaluates the age of the most recent installed Windows update.'
        }
        [pscustomobject]@{
            Name            = 'Services'
            Category        = 'Availability'
            FunctionName    = 'Invoke-InfraPulseServiceCheck'
            RequiresWindows = $true
            Description     = 'Verifies explicitly configured Windows services and expected states.'
        }
        [pscustomobject]@{
            Name            = 'Certificates'
            Category        = 'Security'
            FunctionName    = 'Invoke-InfraPulseCertificateCheck'
            RequiresWindows = $true
            Description     = 'Finds expired and soon-to-expire certificates in configured LocalMachine stores.'
        }
        [pscustomobject]@{
            Name            = 'EventLog'
            Category        = 'Reliability'
            FunctionName    = 'Invoke-InfraPulseEventLogCheck'
            RequiresWindows = $true
            Description     = 'Counts recent critical and error events and identifies the noisiest providers.'
        }
        [pscustomobject]@{
            Name            = 'Dns'
            Category        = 'Connectivity'
            FunctionName    = 'Invoke-InfraPulseDnsCheck'
            RequiresWindows = $false
            Description     = 'Resolves configured DNS targets from the evaluated host.'
        }
        [pscustomobject]@{
            Name            = 'Tcp'
            Category        = 'Connectivity'
            FunctionName    = 'Invoke-InfraPulseTcpCheck'
            RequiresWindows = $false
            Description     = 'Tests configured TCP endpoints with deterministic connection timeouts.'
        }
        [pscustomobject]@{
            Name            = 'Tls'
            Category        = 'Security'
            FunctionName    = 'Invoke-InfraPulseTlsCheck'
            RequiresWindows = $false
            Description     = 'Validates TLS handshakes, certificate identity, chain trust, protocol, and expiry for configured endpoints.'
        }
        [pscustomobject]@{
            Name            = 'TimeSync'
            Category        = 'Connectivity'
            FunctionName    = 'Invoke-InfraPulseTimeSyncCheck'
            RequiresWindows = $false
            Description     = 'Queries NTP servers and calculates the local clock offset using SNTP timestamps.'
        }
    )
}
