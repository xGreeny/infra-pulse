function Invoke-InfraPulseServiceCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $requiredServices = @($Settings.Required)
    if ($requiredServices.Count -eq 0) {
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Services' -Category 'Availability' -ComputerName $Context.ComputerName -Target 'Configured services' -Message 'No required services are configured.' -Recommendation 'Add service definitions under Checks.Services.Required when service-state validation is required.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        param($ServiceDefinitions)

        if ($env:OS -ne 'Windows_NT') {
            throw 'The Services check requires a Windows target.'
        }

        foreach ($definition in @($ServiceDefinitions)) {
            $serviceName = [string]$definition.Name
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                $startMode = $null
                try {
                    if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
                        $escapedName = $serviceName.Replace("'", "''")
                        $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$escapedName'" -ErrorAction Stop
                        $startMode = $cimService.StartMode
                    }
                    else {
                        $escapedName = $serviceName.Replace("'", "''")
                        $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name = '$escapedName'" -ErrorAction Stop
                        $startMode = $wmiService.StartMode
                    }
                }
                catch {
                    $startMode = $null
                }

                [pscustomobject]@{
                    Name        = $service.Name
                    DisplayName = $service.DisplayName
                    Status      = $service.Status.ToString()
                    StartMode   = $startMode
                    Exists      = $true
                }
            }
            catch {
                [pscustomobject]@{
                    Name        = $serviceName
                    DisplayName = $serviceName
                    Status      = 'NotFound'
                    StartMode   = $null
                    Exists      = $false
                }
            }
        }
    }

    $raw = @(Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock -ArgumentList @(, $requiredServices))
    $stopwatch.Stop()

    $results = @()
    for ($index = 0; $index -lt $requiredServices.Count; $index++) {
        $definition = $requiredServices[$index]
        $service = $raw | Where-Object { $_.Name -eq [string]$definition.Name } | Select-Object -First 1

        if ($null -eq $service -or -not [bool]$service.Exists) {
            $status = [string]$definition.Severity
            $message = "Required service '$($definition.Name)' was not found."
            $recommendation = 'Validate the service name and installation state before changing the configuration.'
            $observed = 'NotFound'
            $evidence = [ordered]@{
                Name           = [string]$definition.Name
                ExpectedStatus = [string]$definition.ExpectedStatus
                Exists         = $false
            }
        }
        elseif ([string]$service.Status -ne [string]$definition.ExpectedStatus) {
            $status = [string]$definition.Severity
            $message = "Service '$($service.DisplayName)' is $($service.Status); expected $($definition.ExpectedStatus)."
            $recommendation = 'Review dependent services and recent changes, then restore the expected state using the approved operational procedure.'
            $observed = [string]$service.Status
            $evidence = [ordered]@{
                Name           = [string]$service.Name
                DisplayName    = [string]$service.DisplayName
                Status         = [string]$service.Status
                ExpectedStatus = [string]$definition.ExpectedStatus
                StartMode      = [string]$service.StartMode
                Exists         = $true
            }
        }
        else {
            $status = 'Healthy'
            $message = "Service '$($service.DisplayName)' is $($service.Status)."
            $recommendation = ''
            $observed = [string]$service.Status
            $evidence = [ordered]@{
                Name           = [string]$service.Name
                DisplayName    = [string]$service.DisplayName
                Status         = [string]$service.Status
                ExpectedStatus = [string]$definition.ExpectedStatus
                StartMode      = [string]$service.StartMode
                Exists         = $true
            }
        }

        $warningThreshold = $null
        $criticalThreshold = $null
        if ([string]$definition.Severity -eq 'Critical') {
            $criticalThreshold = "Expected: $($definition.ExpectedStatus)"
        }
        else {
            $warningThreshold = "Expected: $($definition.ExpectedStatus)"
        }

        $results += New-InfraPulseResult -Status $status -CheckName 'Services' -Category 'Availability' -ComputerName $Context.ComputerName -Target ([string]$definition.Name) -Message $message -ObservedValue $observed -WarningThreshold $warningThreshold -CriticalThreshold $criticalThreshold -Recommendation $recommendation -Evidence $evidence -DurationMs ($stopwatch.Elapsed.TotalMilliseconds / $requiredServices.Count)
    }

    return $results
}
