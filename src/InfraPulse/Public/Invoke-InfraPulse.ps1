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
        Path to a .psd1 configuration file. When neither ConfigurationPath nor Configuration is supplied, InfraPulse discovers a configuration from the INFRAPULSE_CONFIG environment variable or an infra-pulse.psd1 file in the working directory before falling back to built-in defaults; the report records the effective source in ConfigurationSource.

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

    .PARAMETER ThrottleLimit
        Maximum number of computers scanned concurrently. Multiple targets are scanned in parallel runspaces unless ThrottleLimit is 1 or FailFast is set, which force sequential processing.

    .PARAMETER FailFast
        Stops at the first connection or check failure instead of returning a control result and continuing. Implies sequential processing.

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

        [ValidateSet('Disk', 'Memory', 'Uptime', 'PendingReboot', 'PatchAge', 'Services', 'Certificates', 'EventLog', 'Dns', 'Tcp', 'Tls', 'TimeSync')]
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

        [Parameter(ParameterSetName = 'ComputerName')]
        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 8,

        [switch]$FailFast,

        [string[]]$Tag = @()
    )

    begin {
        $resolved = Resolve-InfraPulseConfiguration -ConfigurationPath $ConfigurationPath -Configuration $Configuration
        $resolvedConfiguration = $resolved.Configuration
        $configurationSource = [string]$resolved.Source
        $runId = [guid]::NewGuid().ToString()
        $configurationFingerprint = Get-InfraPulseConfigurationFingerprint -Configuration $resolvedConfiguration
        $pipelineTargets = New-Object System.Collections.Generic.List[string]
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
                    New-InfraPulseConnectionFailureReport -ComputerName $requestedName -ErrorMessage $message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint -ConfigurationSource $configurationSource
                    continue
                }

                $context = [pscustomobject]@{
                    RequestedComputerName = $requestedName
                    ComputerName          = $requestedName
                    Session               = $currentSession
                    OwnsSession           = $false
                }

                try {
                    Invoke-InfraPulseTarget -Context $context -Configuration $resolvedConfiguration -Checks $selectedChecks -FailFast:$FailFast -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint -ConfigurationSource $configurationSource
                }
                catch {
                    if ($FailFast -or -not [bool]$resolvedConfiguration.General.ContinueOnError) {
                        throw
                    }
                    New-InfraPulseExecutionFailureReport -RequestedComputerName $requestedName -ComputerName $context.ComputerName -ErrorMessage $_.Exception.Message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint -ConfigurationSource $configurationSource
                }
            }
        }
        else {
            foreach ($target in $ComputerName) {
                [void]$pipelineTargets.Add([string]$target)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Session') {
            return
        }

        $targets = @($pipelineTargets.ToArray())
        if ($targets.Count -eq 0) {
            return
        }

        $effectivePort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { 0 }
        $targetParameters = @{
            Configuration            = $resolvedConfiguration
            Checks                   = $selectedChecks
            Tags                     = $normalizedTags
            RunId                    = $runId
            ConfigurationFingerprint = $configurationFingerprint
            ConfigurationSource      = $configurationSource
            Authentication           = $Authentication
            UseSSL                   = [bool]$UseSSL
            Port                     = $effectivePort
            FailFast                 = [bool]$FailFast
        }
        if ($null -ne $Credential) {
            $targetParameters.Credential = $Credential
        }

        # FailFast requires deterministic early termination, so it always runs
        # sequentially; parallel runspaces only pay off for multiple targets.
        $useParallel = $targets.Count -gt 1 -and $ThrottleLimit -gt 1 -and -not $FailFast
        if (-not $useParallel) {
            foreach ($target in $targets) {
                Invoke-InfraPulseComputerTarget -TargetName $target @targetParameters
            }
            return
        }

        $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        [void]$initialSessionState.ImportPSModule($script:InfraPulseManifestPath)
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $initialSessionState, $Host)
        $runspacePool.Open()
        $workers = New-Object System.Collections.Generic.List[object]

        try {
            foreach ($target in $targets) {
                $workerParameters = @{} + $targetParameters
                $workerParameters.TargetName = [string]$target

                $worker = [powershell]::Create()
                $worker.RunspacePool = $runspacePool
                [void]$worker.AddScript('param($WorkerParameters) & (Get-Module -Name InfraPulse) { param($p) Invoke-InfraPulseComputerTarget @p } $WorkerParameters').AddArgument($workerParameters)
                $workerRecord = @{
                    Target     = [string]$target
                    PowerShell = $worker
                    Handle     = $worker.BeginInvoke()
                }
                [void]$workers.Add($workerRecord)
            }

            # Results are emitted in input order; workers that finish ahead of
            # the cursor simply wait in their runspaces.
            foreach ($workerEntry in @($workers.ToArray())) {
                try {
                    $workerEntry.PowerShell.EndInvoke($workerEntry.Handle)
                }
                catch {
                    New-InfraPulseExecutionFailureReport -RequestedComputerName ([string]$workerEntry.Target) -ComputerName ([string]$workerEntry.Target) -ErrorMessage $_.Exception.Message -Tags $normalizedTags -RunId $runId -ConfigurationFingerprint $configurationFingerprint -ConfigurationSource $configurationSource
                }
                finally {
                    $workerEntry.PowerShell.Dispose()
                }
            }
        }
        finally {
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }
}
