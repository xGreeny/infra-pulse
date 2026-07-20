function Get-InfraPulseConfigurationTemplate {
    [CmdletBinding()]
    param(
        [switch]$Minimal
    )

    if ($Minimal) {
        return @'
@{
    SchemaVersion = '1.0'

    General = @{
        DefaultChecks = @('Disk', 'Memory', 'Uptime', 'PendingReboot')
    }

    Checks = @{
        Disk = @{
            WarningFreePercent  = 20
            CriticalFreePercent = 10
            WarningFreeGB       = 20
            CriticalFreeGB      = 10
        }

        Memory = @{
            WarningAvailablePercent  = 20
            CriticalAvailablePercent = 10
        }

        Uptime = @{
            WarningDays  = 45
            CriticalDays = 90
        }
    }
}
'@
    }

    return @'
@{
    SchemaVersion = '1.0'

    General = @{
        # Executed when Invoke-InfraPulse is called without -Check.
        DefaultChecks = @(
            'Disk'
            'Memory'
            'Uptime'
            'PendingReboot'
            'Services'
            'Certificates'
            'EventLog'
            'Dns'
            'Tcp'
            'TimeSync'
        )

        ContinueOnError          = $true
        ConnectionTimeoutSeconds = 15
        IncludeInventory         = $true
    }

    Checks = @{
        Disk = @{
            Enabled             = $true
            Include             = @('*')
            Exclude             = @('A:')
            WarningFreePercent  = 20
            CriticalFreePercent = 10
            WarningFreeGB       = 20
            CriticalFreeGB      = 10
        }

        Memory = @{
            Enabled                  = $true
            WarningAvailablePercent  = 20
            CriticalAvailablePercent = 10
        }

        Uptime = @{
            Enabled      = $true
            WarningDays  = 45
            CriticalDays = 90
        }

        PendingReboot = @{
            Enabled       = $true
            PendingStatus = 'Warning'
        }

        Services = @{
            Enabled = $true
            Required = @(
                @{
                    Name           = 'EventLog'
                    ExpectedStatus = 'Running'
                    Severity       = 'Critical'
                }
                @{
                    Name           = 'Winmgmt'
                    ExpectedStatus = 'Running'
                    Severity       = 'Critical'
                }
            )
        }

        Certificates = @{
            Enabled = $true
            StorePaths = @(
                'Cert:\LocalMachine\My'
                'Cert:\LocalMachine\WebHosting'
            )
            WarningDays            = 30
            CriticalDays           = 14
            SubjectExcludePatterns = @()

            # Wildcard patterns matched against the certificate issuer. Useful for
            # auto-rotated short-lived certificates whose thumbprint changes on
            # every rotation.
            IssuerExcludePatterns = @(
                # 'CN=MS-Organization-P2P-Access*'
            )

            ThumbprintExclude = @()
            RequirePrivateKey = $false

            # Certificates whose total lifetime (NotAfter - NotBefore) is shorter
            # than this many days are excluded from the expiry evaluation.
            # 0 keeps every certificate.
            MinTotalLifetimeDays = 0
        }

        EventLog = @{
            Enabled          = $true
            Logs             = @('System', 'Application')
            LookbackHours    = 24
            Levels           = @(1, 2)
            WarningCount     = 25
            CriticalCount    = 100
            MaxEvents        = 500
            ExcludeProviders = @()
            ExcludeEventIds  = @()
            IncludeMessages  = $false
        }

        Dns = @{
            Enabled   = $true
            QueryType = 'A'
            Server    = ''
            Targets   = @(
                # 'login.microsoftonline.com'
                # @{ Name = '_ldap._tcp.dc._msdcs.contoso.invalid'; Type = 'SRV' }
            )
        }

        Tcp = @{
            Enabled             = $true
            TimeoutMilliseconds = 3000
            Endpoints = @(
                # @{ Name = 'Microsoft identity'; Host = 'login.microsoftonline.com'; Port = 443 }
                # @{ Name = 'Domain controller LDAP'; Host = 'dc01.contoso.invalid'; Port = 389 }
            )
        }

        TimeSync = @{
            Enabled               = $false
            Servers               = @('time.windows.com')
            TimeoutMilliseconds   = 3000
            WarningOffsetSeconds  = 2
            CriticalOffsetSeconds = 5
        }
    }
}
'@
}
