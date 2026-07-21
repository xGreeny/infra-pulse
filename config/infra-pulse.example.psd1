@{
    SchemaVersion = '1.0'

    General = @{
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
            'Tls'
        )
        ContinueOnError          = $true
        ConnectionTimeoutSeconds = 15
        IncludeInventory         = $true
    }

    Checks = @{
        Disk = @{
            Include             = @('*')
            Exclude             = @('A:')
            WarningFreePercent  = 18
            CriticalFreePercent = 8
            WarningFreeGB       = 30
            CriticalFreeGB      = 12
        }

        Memory = @{
            WarningAvailablePercent  = 20
            CriticalAvailablePercent = 10
        }

        Uptime = @{
            WarningDays  = 45
            CriticalDays = 90
        }

        PendingReboot = @{
            PendingStatus = 'Warning'

            # Exclude indicators that agents and updates re-create continuously.
            ExcludeReasons = @(
                # 'Pending file rename operations'
            )
        }

        PatchAge = @{
            WarningDays  = 45
            CriticalDays = 90
        }

        Services = @{
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
                @{
                    Name           = 'W32Time'
                    ExpectedStatus = 'Running'
                    Severity       = 'Warning'
                }
            )
        }

        Certificates = @{
            StorePaths = @(
                'Cert:\LocalMachine\My'
                'Cert:\LocalMachine\WebHosting'
            )
            WarningDays            = 30
            CriticalDays           = 14
            SubjectExcludePatterns = @()
            IssuerExcludePatterns  = @(
                # 'CN=MS-Organization-P2P-Access*'
            )
            ThumbprintExclude      = @()
            RequirePrivateKey      = $false
            MinTotalLifetimeDays   = 0

            # Short-lived certificates (total lifetime <= WarningDays) are
            # reported as auto-rotating and only alert when rotation breaks.
            TreatShortLivedAsRotating = $true
        }

        EventLog = @{
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
            QueryType = 'A'
            Server    = ''
            Targets   = @(
                'login.microsoftonline.com'
                'github.com'
            )
        }

        Tcp = @{
            TimeoutMilliseconds = 3000
            Endpoints = @(
                @{
                    Name = 'Microsoft identity'
                    Host = 'login.microsoftonline.com'
                    Port = 443
                }
                @{
                    Name = 'GitHub HTTPS'
                    Host = 'github.com'
                    Port = 443
                }
            )
        }

        Tls = @{
            TimeoutMilliseconds = 5000
            WarningDays         = 30
            CriticalDays        = 14
            RequireTrustedChain = $true
            RequireNameMatch    = $true
            Endpoints = @(
                @{
                    Name = 'Microsoft identity'
                    Host = 'login.microsoftonline.com'
                    Port = 443
                }
                @{
                    Name = 'GitHub HTTPS'
                    Host = 'github.com'
                    Port = 443
                }
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
