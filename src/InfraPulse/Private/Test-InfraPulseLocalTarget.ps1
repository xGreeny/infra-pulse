function Test-InfraPulseLocalTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $normalized = $ComputerName.Trim().ToLowerInvariant()
    if ($normalized -in @('.', 'localhost', '127.0.0.1', '::1')) {
        return $true
    }

    $candidates = @()
    if ($env:COMPUTERNAME) {
        $candidates += $env:COMPUTERNAME.ToLowerInvariant()
    }
    if ([Environment]::MachineName) {
        $candidates += [Environment]::MachineName.ToLowerInvariant()
    }

    try {
        $hostEntry = [System.Net.Dns]::GetHostEntry([Environment]::MachineName)
        if ($hostEntry.HostName) {
            $candidates += $hostEntry.HostName.ToLowerInvariant()
        }
    }
    catch {
        Write-Debug "Local DNS registration could not be resolved: $($_.Exception.Message)"
    }

    return $normalized -in ($candidates | Select-Object -Unique)
}
