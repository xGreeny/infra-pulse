function Invoke-InfraPulseDefenderCheck {
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
            throw 'The Defender check requires a Windows target.'
        }

        if (-not (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ Supported = $false; Error = $null }
        }

        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{ Supported = $false; Error = $_.Exception.Message }
        }

        [pscustomobject]@{
            Supported                   = $true
            Error                       = $null
            AntivirusEnabled            = [bool]$defenderStatus.AntivirusEnabled
            RealTimeProtectionEnabled   = [bool]$defenderStatus.RealTimeProtectionEnabled
            AntivirusSignatureAge       = [int]$defenderStatus.AntivirusSignatureAge
            AntivirusSignatureLastUpdated = $defenderStatus.AntivirusSignatureLastUpdated
            AMEngineVersion             = [string]$defenderStatus.AMEngineVersion
        }
    }

    $defender = Invoke-InfraPulseCommand -Context $Context -ScriptBlock $scriptBlock
    $stopwatch.Stop()

    if (-not [bool]$defender.Supported) {
        $skipMessage = 'Microsoft Defender interfaces are unavailable on the target; a third-party antivirus may be active.'
        return New-InfraPulseResult -Status 'Skipped' -CheckName 'Defender' -Category 'Security' -ComputerName $Context.ComputerName -Target 'Microsoft Defender' -Message $skipMessage -Recommendation 'Confirm which endpoint-protection product covers this host and monitor it through its own tooling.' -Evidence ([ordered]@{ Error = [string]$defender.Error }) -DurationMs $stopwatch.Elapsed.TotalMilliseconds
    }

    $signatureAge = [int]$defender.AntivirusSignatureAge

    if (-not [bool]$defender.AntivirusEnabled -or -not [bool]$defender.RealTimeProtectionEnabled) {
        $status = 'Critical'
        $disabledPart = if (-not [bool]$defender.AntivirusEnabled) { 'antivirus engine' } else { 'real-time protection' }
        $message = "Microsoft Defender $disabledPart is disabled."
        $recommendation = 'Re-enable Microsoft Defender protection or document the managed replacement; an unprotected host is a critical exposure.'
    }
    elseif ($signatureAge -ge [int]$Settings.SignatureCriticalDays) {
        $status = 'Critical'
        $message = "Defender signatures are $signatureAge day(s) old."
        $recommendation = 'Restore signature updates immediately; validate update sources and connectivity.'
    }
    elseif ($signatureAge -ge [int]$Settings.SignatureWarningDays) {
        $status = 'Warning'
        $message = "Defender signatures are $signatureAge day(s) old."
        $recommendation = 'Check why signature updates lag behind; the host falls behind current threat coverage.'
    }
    else {
        $status = 'Healthy'
        $message = "Real-time protection is enabled; signatures are $signatureAge day(s) old."
        $recommendation = ''
    }

    $evidence = [ordered]@{
        AntivirusEnabled              = [bool]$defender.AntivirusEnabled
        RealTimeProtectionEnabled     = [bool]$defender.RealTimeProtectionEnabled
        AntivirusSignatureAge         = $signatureAge
        AntivirusSignatureLastUpdated = $defender.AntivirusSignatureLastUpdated
        AMEngineVersion               = [string]$defender.AMEngineVersion
    }

    return New-InfraPulseResult -Status $status -CheckName 'Defender' -Category 'Security' -ComputerName $Context.ComputerName -Target 'Microsoft Defender' -Message $message -ObservedValue ("{0} day(s)" -f $signatureAge) -WarningThreshold (">= {0} days signature age" -f $Settings.SignatureWarningDays) -CriticalThreshold (">= {0} days signature age or disabled protection" -f $Settings.SignatureCriticalDays) -Recommendation $recommendation -Evidence $evidence -DurationMs $stopwatch.Elapsed.TotalMilliseconds
}
