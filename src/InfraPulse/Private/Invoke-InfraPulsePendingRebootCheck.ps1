function Invoke-InfraPulsePendingRebootCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scriptBlock = {
        if ($env:OS -ne 'Windows_NT') {
            throw 'The PendingReboot check requires a Windows target.'
        }

        $reasons = New-Object System.Collections.Generic.List[string]

        $componentBasedServicing = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        if (Test-Path -LiteralPath $componentBasedServicing) {
            $reasons.Add('Component Based Servicing')
        }

        $windowsUpdate = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        if (Test-Path -LiteralPath $windowsUpdate) {
            $reasons.Add('Windows Update')
        }

        $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        try {
            $pendingRename = (Get-ItemProperty -LiteralPath $sessionManager -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
            if ($null -ne $pendingRename -and @($pendingRename).Count -gt 0) {
                $reasons.Add('Pending file rename operations')
            }
        }
        catch {
            Write-Debug "PendingFileRenameOperations is not present: $($_.Exception.Message)"
        }

        $updateExeVolatile = 'HKLM:\SOFTWARE\Microsoft\Updates'
        try {
            $volatileValue = (Get-ItemProperty -LiteralPath $updateExeVolatile -Name UpdateExeVolatile -ErrorAction Stop).UpdateExeVolatile
            if ([int]$volatileValue -ne 0) {
                $reasons.Add('UpdateExeVolatile')
            }
        }
        catch {
            Write-Debug "UpdateExeVolatile is not present: $($_.Exception.Message)"
        }

        try {
            $activeName = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
            $configuredName = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
            if ($activeName -ne $configuredName) {
                $reasons.Add('Computer rename')
            }
        }
        catch {
            Write-Debug "Computer-name comparison was unavailable: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name Invoke-CimMethod -ErrorAction SilentlyContinue) {
                $ccmResult = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
                if ($ccmResult.RebootPending -or $ccmResult.IsHardRebootPending) {
                    $reasons.Add('Configuration Manager client')
                }
            }
        }
        catch {
            Write-Debug "Configuration Manager reboot state was unavailable: $($_.Exception.Message)"
        }

        [pscustomobject]@{
            Pending = $reasons.Count -gt 0
            Reasons = @($reasons)
        }
    }

    $pending = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if ([bool]$pending.Pending) {
        $status = [string]$Settings.PendingStatus
        $reasonText = @($pending.Reasons) -join ', '
        $message = "A reboot is pending: $reasonText."
        $recommendation = 'Schedule a controlled restart, confirm service restoration, and verify that all reboot indicators clear afterward.'
    }
    else {
        $status = 'Healthy'
        $message = 'No supported pending-reboot indicators were detected.'
        $recommendation = ''
    }

    $evidence = [ordered]@{
        Pending = [bool]$pending.Pending
        Reasons = @($pending.Reasons)
    }

    $warningThreshold = $null
    $criticalThreshold = $null
    if ([string]$Settings.PendingStatus -eq 'Critical') {
        $criticalThreshold = 'Any supported reboot indicator'
    }
    else {
        $warningThreshold = 'Any supported reboot indicator'
    }

    return New-InfraPulseResult -Status $status -CheckName 'PendingReboot' -Category 'Lifecycle' -ComputerName $Context.ComputerName -Target 'Operating system' -Message $message -ObservedValue ([bool]$pending.Pending) -WarningThreshold $warningThreshold -CriticalThreshold $criticalThreshold -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
