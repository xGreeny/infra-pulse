function Get-DefaultInfraPulseConfiguration {
    [CmdletBinding()]
    param()

    [ordered]@{
        SchemaVersion = '1.0'
        General       = [ordered]@{
            DefaultChecks           = @(
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
                'TimeSync'
            )
            ContinueOnError         = $true
            ConnectionTimeoutSeconds = 15
            IncludeInventory        = $true
        }
        Checks        = [ordered]@{
            Disk          = [ordered]@{
                Enabled              = $true
                Include              = @('*')
                Exclude              = @('A:')
                WarningFreePercent   = 20
                CriticalFreePercent  = 10
                WarningFreeGB        = 20
                CriticalFreeGB       = 10
            }
            Memory        = [ordered]@{
                Enabled                  = $true
                WarningAvailablePercent  = 20
                CriticalAvailablePercent = 10
            }
            Uptime        = [ordered]@{
                Enabled      = $true
                WarningDays  = 45
                CriticalDays = 90
            }
            PendingReboot = [ordered]@{
                Enabled       = $true
                PendingStatus = 'Warning'
            }
            Services      = [ordered]@{
                Enabled  = $true
                Required = @(
                    [ordered]@{
                        Name           = 'EventLog'
                        ExpectedStatus = 'Running'
                        Severity       = 'Critical'
                    }
                    [ordered]@{
                        Name           = 'Winmgmt'
                        ExpectedStatus = 'Running'
                        Severity       = 'Critical'
                    }
                )
            }
            Certificates  = [ordered]@{
                Enabled                = $true
                StorePaths             = @(
                    'Cert:\LocalMachine\My'
                    'Cert:\LocalMachine\WebHosting'
                )
                WarningDays            = 30
                CriticalDays           = 14
                SubjectExcludePatterns = @()
                IssuerExcludePatterns  = @()
                ThumbprintExclude      = @()
                RequirePrivateKey      = $false
                MinTotalLifetimeDays   = 0
            }
            EventLog      = [ordered]@{
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
            Dns           = [ordered]@{
                Enabled   = $true
                QueryType = 'A'
                Server    = ''
                Targets   = @()
            }
            Tcp           = [ordered]@{
                Enabled             = $true
                TimeoutMilliseconds = 3000
                Endpoints           = @()
            }
            Tls           = [ordered]@{
                Enabled             = $true
                TimeoutMilliseconds = 5000
                WarningDays         = 30
                CriticalDays        = 14
                RequireTrustedChain = $true
                RequireNameMatch    = $true
                Endpoints           = @()
            }
            TimeSync      = [ordered]@{
                Enabled               = $false
                Servers               = @('time.windows.com')
                TimeoutMilliseconds   = 3000
                WarningOffsetSeconds  = 2
                CriticalOffsetSeconds = 5
            }
        }
    }
}
