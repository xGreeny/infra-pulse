function Invoke-InfraPulse {
    <#
    .SYNOPSIS
        Runs read-only infrastructure health checks.

    .DESCRIPTION
        Evaluates one or more hosts locally or through PowerShell remoting. The command returns structured InfraPulse.Report objects and does not change target state.

        Windows-specific checks use built-in CIM, service, certificate, and event-log interfaces. DNS, TCP, and SNTP checks can run on any target that supports the required .NET APIs.

    .PARAMETER ComputerName
        One or more target computer names. Localhost is used by default. Remote targets use WSMan PowerShell remoting.

    .PARAMETER Session
        Existing PSSession objects. InfraPulse never closes sessions supplied by the caller.

    .PARAMETER ConfigurationPath
        Path to a .psd1 configuration file.

    .PARAMETER Configuration
        Configuration overrides supplied as a hashtable.

    .PARAMETER Check
        Runs only the selected checks. An explicit selection overrides each check's Enabled value.

    .PARAMETER Credential
        Credential used when InfraPulse creates remote sessions. Credentials are not persisted.

    .PARAMETER Authentication
        PowerShell remoting authentication mechanism.

    .PARAMETER UseSSL
        Uses HTTPS for WSMan remoting.

    .PARAMETER Port
        Overrides the remoting port.

    .PARAMETER FailFast
        Stops at the first connection or check failure instead of returning a control result and continuing.

    .PARAMETER Tag
        Adds user-defined tags to every returned report.

    .EXAMPLE
        Invoke-InfraPulse

        Runs the enabled default checks against the local computer.

    .EXAMPLE
        $report = Invoke-InfraPulse -ComputerName 'srv-app-01' -ConfigurationPath .\infra-pulse.psd1 -Credential (Get-Credential)

        Connects to a remote host through WSMan and applies a configuration file.

    .EXAMPLE
        Get-PSSession | Invoke-InfraPulse -Check Disk, Memory, PendingReboot

        Reuses caller-owned sessions and runs an explicit subset of checks.

    .EXAMPLE
        Invoke-InfraPulse -ComputerName 'srv-01', 'srv-02' | Export-InfraPulseReport -Path .\out\health.html -Force

        Scans two hosts and writes one self-contained HTML report.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'Name', 'DNSHostName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = @('localhost'),

        [Parameter(Mandatory, ParameterSetName = 'Session', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [ValidateNotNullOrEmpty()]
        [string]$ConfigurationPath,

        [ValidateNotNull()]
        [System.Collections.IDictionary]$Configuration,

        [ValidateSet('Disk', 'Memory', 'Uptime', 'PendingReboot', 'Services', 'Certificates', 'EventLog', 'Dns', 'Tcp', 'Tls', 'TimeSync')]
        [string[]]$Check,

        [Parameter(ParameterSetName = 'ComputerName')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(ParameterSetName = 'ComputerName')]
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',

        [Parameter(ParameterSetName = 'ComputerName')]
        [switch]$UseSSL,

        [Parameter(ParameterSetName = 'ComputerName')]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [switch]$FailFast,

        [string[]]$Tag = @()
    )

    begin {
        $resolvedConfiguration = Resolve-InfraPulseConfiguration -ConfigurationPath $ConfigurationPath -Configuration $Configuration
        $runId = [guid]::NewGuid().ToString()
        $configurationFingerprint = Get-InfraPulseConfigurationFingerprint -Configuration $resolvedConfiguration
        $catalog = @(Get-InfraPulseCheckCatalog)
        $normalizedTags = @(
            $Tag |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Select-Object -Unique
        )

        if ($PSBoundParameters.ContainsKey('Check')) {
            $selectedChecks = @($Check | Select-Object -Unique)
        }
        else {
            $selectedChecks = @(
                foreach ($defaultCheck in @($resolvedConfiguration.General.DefaultChecks)) {
                    $definition = $catalog | Where-Object { $_.Name -eq [string]$defaultCheck } | Select-Object -First 1
                    if ($null -ne $definition -and [bool]$resolvedConfiguration.Checks[$definition.Name].Enabled) {
                        $definition.Name
                    }
                }
            )
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Session') {
            foreach ($currentSession in $Session) {
                $requestedName = [string]$currentSession.ComputerName
                if ([string]::IsNullOrWhiteSpace($requestedName)) {
                    $requestedName = [string]$currentSession.InstanceId
                }

                if ($currentSession.State -ne 'Opened') {
                    $message = "PSSession state is '$($currentSession.State)'."
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw "Cannot use session for '$requestedName': $message"
                    }
                    New-InfraPulseConnectionFailureReport -ComputerName $requestedName -ErrorMessage $message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                    continue
                }

                $context = [pscustomobject]@{
                    RequestedComputerName = $requestedName
                    ComputerName          = $requestedName
                    Session               = $currentSession
                    OwnsSession           = $false
                }

                try {
                    Invoke-InfraPulseTarget -Context $context -Configuration $resolvedConfiguration -Checks $selectedChecks -FailFast:$FailFast -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                }
                catch {
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw
                    }
                    New-InfraPulseExecutionFailureReport -RequestedComputerName $requestedName -ComputerName $context.ComputerName -ErrorMessage $_.Exception.Message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                }
            }
        }
        else {
            foreach ($target in $ComputerName) {
                $targetName = ([string]$target).Trim()
                if ([string]::IsNullOrWhiteSpace($targetName)) {
                    $message = 'ComputerName cannot be empty or whitespace.'
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw $message
                    }
                    $invalidTargetName = '<empty>'
                    New-InfraPulseConnectionFailureReport -ComputerName $invalidTargetName -ErrorMessage $message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                    continue
                }

                $ownedSession = $null
                $context = $null
                $connectionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                try {
                    if (Test-InfraPulseLocalTarget -ComputerName $targetName) {
                        $connectionStopwatch.Stop()
                        $context = [pscustomobject]@{
                            RequestedComputerName = $targetName
                            ComputerName          = [Environment]::MachineName
                            Session               = $null
                            OwnsSession           = $false
                        }
                    }
                    else {
                        $sessionOptions = New-PSSessionOption -OpenTimeout ([int]$resolvedConfiguration.General.ConnectionTimeoutSeconds * 1000) -OperationTimeout ([int]$resolvedConfiguration.General.ConnectionTimeoutSeconds * 4000)
                        $sessionParameters = @{
                            ComputerName  = $targetName
                            Authentication = $Authentication
                            SessionOption = $sessionOptions
                            ErrorAction   = 'Stop'
                        }
                        if ($null -ne $Credential) {
                            $sessionParameters.Credential = $Credential
                        }
                        if ($UseSSL) {
                            $sessionParameters.UseSSL = $true
                        }
                        if ($PSBoundParameters.ContainsKey('Port')) {
                            $sessionParameters.Port = $Port
                        }

                        Write-Verbose "[$targetName] Opening PowerShell remoting session."
                        $ownedSession = New-PSSession @sessionParameters
                        $connectionStopwatch.Stop()
                        $context = [pscustomobject]@{
                            RequestedComputerName = $targetName
                            ComputerName          = $targetName
                            Session               = $ownedSession
                            OwnsSession           = $true
                        }
                    }
                }
                catch {
                    $connectionStopwatch.Stop()
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw
                    }
                    New-InfraPulseConnectionFailureReport -ComputerName $targetName -ErrorMessage $_.Exception.Message -DurationMs $connectionStopwatch.Elapsed.TotalMilliseconds -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                    continue
                }

                try {
                    Invoke-InfraPulseTarget -Context $context -Configuration $resolvedConfiguration -Checks $selectedChecks -FailFast:$FailFast -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                }
                catch {
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw
                    }
                    New-InfraPulseExecutionFailureReport -RequestedComputerName $targetName -ComputerName $context.ComputerName -ErrorMessage $_.Exception.Message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint
                }
                finally {
                    if ($null -ne $ownedSession) {
                        Write-Verbose "[$targetName] Closing PowerShell remoting session."
                        Remove-PSSession -Session $ownedSession -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}
