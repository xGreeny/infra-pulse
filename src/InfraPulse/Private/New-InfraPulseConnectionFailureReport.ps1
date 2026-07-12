function New-InfraPulseConnectionFailureReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [double]$DurationMs,

        [string[]]$Tags = @()
    )

    $result = New-InfraPulseResult -Status 'Critical' -CheckName 'Connection' -Category 'Control' -ComputerName $ComputerName -Target $ComputerName -Message "Unable to establish a PowerShell remoting session to '$ComputerName'." -ObservedValue $false -CriticalThreshold 'Remote session must open' -Recommendation 'Validate WinRM/WSMan, authentication, firewall policy, name resolution, and administrative access.' -Evidence ([ordered]@{ ComputerName = $ComputerName; Error = $ErrorMessage }) -DurationMs $DurationMs -ErrorMessage $ErrorMessage
    return New-InfraPulseReport -RequestedComputerName $ComputerName -ComputerName $ComputerName -Inventory $null -Results @($result) -DurationMs $DurationMs -Tags $Tags
}
