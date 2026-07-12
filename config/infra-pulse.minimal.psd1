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

        PendingReboot = @{
            PendingStatus = 'Warning'
        }
    }
}
