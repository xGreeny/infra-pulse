function Invoke-InfraPulseComputerTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$TargetName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Configuration,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Checks,

        [string[]]$Tags = @(),

        [string]$RunId = '',

        [string]$ConfigurationFingerprint = '',

        [string]$ConfigurationSource = '',

        [string]$EnvironmentName = '',

        [System.Management.Automation.PSCredential]$Credential,

        [string]$Authentication = 'Default',

        [bool]$UseSSL = $false,

        [int]$Port = 0,

        [bool]$FailFast = $false
    )

    $reportParameters = @{
        Tags                     = $Tags
        RunId                    = $RunId
        ConfigurationFingerprint = $ConfigurationFingerprint
        ConfigurationSource      = $ConfigurationSource
        EnvironmentName          = $EnvironmentName
    }

    $trimmedName = ([string]$TargetName).Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedName)) {
        $message = 'ComputerName cannot be empty or whitespace.'
        if ($FailFast -or -not [bool]$Configuration.General.ContinueOnError) {
            throw $message
        }
        $invalidTargetName = '<empty>'
        return New-InfraPulseConnectionFailureReport -ComputerName $invalidTargetName -ErrorMessage $message @reportParameters
    }

    $ownedSession = $null
    $context = $null
    $connectionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Test-InfraPulseLocalTarget -ComputerName $trimmedName) {
            $connectionStopwatch.Stop()
            $context = [pscustomobject]@{
                RequestedComputerName = $trimmedName
                ComputerName          = [Environment]::MachineName
                Session               = $null
                OwnsSession           = $false
            }
        }
        else {
            $sessionOptions = New-PSSessionOption -OpenTimeout ([int]$Configuration.General.ConnectionTimeoutSeconds * 1000) -OperationTimeout ([int]$Configuration.General.ConnectionTimeoutSeconds * 4000)
            $sessionParameters = @{
                ComputerName   = $trimmedName
                Authentication = $Authentication
                SessionOption  = $sessionOptions
                ErrorAction    = 'Stop'
            }
            if ($null -ne $Credential) {
                $sessionParameters.Credential = $Credential
            }
            if ($UseSSL) {
                $sessionParameters.UseSSL = $true
            }
            if ($Port -gt 0) {
                $sessionParameters.Port = $Port
            }

            Write-Verbose "[$trimmedName] Opening PowerShell remoting session."
            $ownedSession = New-PSSession @sessionParameters
            $connectionStopwatch.Stop()
            $context = [pscustomobject]@{
                RequestedComputerName = $trimmedName
                ComputerName          = $trimmedName
                Session               = $ownedSession
                OwnsSession           = $true
            }
        }
    }
    catch {
        $connectionStopwatch.Stop()
        if ($FailFast -or -not [bool]$Configuration.General.ContinueOnError) {
            throw
        }
        return New-InfraPulseConnectionFailureReport -ComputerName $trimmedName -ErrorMessage $_.Exception.Message -DurationMs $connectionStopwatch.Elapsed.TotalMilliseconds @reportParameters
    }

    try {
        Invoke-InfraPulseTarget -Context $context -Configuration $Configuration -Checks $Checks -FailFast:$FailFast -Tags $Tags -RunId $RunId -ConfigurationFingerprint $ConfigurationFingerprint -ConfigurationSource $ConfigurationSource -EnvironmentName $EnvironmentName
    }
    catch {
        if ($FailFast -or -not [bool]$Configuration.General.ContinueOnError) {
            throw
        }
        New-InfraPulseExecutionFailureReport -RequestedComputerName $trimmedName -ComputerName $context.ComputerName -ErrorMessage $_.Exception.Message @reportParameters
    }
    finally {
        if ($null -ne $ownedSession) {
            Write-Verbose "[$trimmedName] Closing PowerShell remoting session."
            Remove-PSSession -Session $ownedSession -ErrorAction SilentlyContinue
        }
    }
}
