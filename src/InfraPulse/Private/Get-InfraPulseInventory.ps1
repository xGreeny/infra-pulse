function Get-InfraPulseInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    $scriptBlock = {
        $isWindowsHost = $env:OS -eq 'Windows_NT'
        $fqdn = $null
        try {
            $fqdn = [System.Net.Dns]::GetHostEntry([Environment]::MachineName).HostName
        }
        catch {
            $fqdn = [Environment]::MachineName
        }

        if ($isWindowsHost) {
            if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
                $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            }
            else {
                $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
                $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            }

            [pscustomobject]@{
                ComputerName       = $env:COMPUTERNAME
                Fqdn               = $fqdn
                Platform           = 'Windows'
                OperatingSystem    = $operatingSystem.Caption
                OperatingSystemSku = $operatingSystem.OperatingSystemSKU
                Version            = $operatingSystem.Version
                BuildNumber        = $operatingSystem.BuildNumber
                Architecture       = $operatingSystem.OSArchitecture
                Manufacturer       = $computerSystem.Manufacturer
                Model              = $computerSystem.Model
                Domain             = $computerSystem.Domain
                PartOfDomain       = [bool]$computerSystem.PartOfDomain
                PowerShellVersion  = $PSVersionTable.PSVersion.ToString()
                PowerShellEdition  = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
                CollectedAtUtc     = [DateTime]::UtcNow
            }
        }
        else {
            [pscustomobject]@{
                ComputerName       = [Environment]::MachineName
                Fqdn               = $fqdn
                Platform           = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
                OperatingSystem    = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
                OperatingSystemSku = $null
                Version            = [Environment]::OSVersion.Version.ToString()
                BuildNumber        = $null
                Architecture       = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
                Manufacturer       = $null
                Model              = $null
                Domain             = $null
                PartOfDomain       = $false
                PowerShellVersion  = $PSVersionTable.PSVersion.ToString()
                PowerShellEdition  = $PSVersionTable.PSEdition
                CollectedAtUtc     = [DateTime]::UtcNow
            }
        }
    }

    return Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
}
