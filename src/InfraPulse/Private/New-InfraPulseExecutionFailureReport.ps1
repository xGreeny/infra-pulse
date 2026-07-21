function New-InfraPulseExecutionFailureReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RequestedComputerName,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [double]$DurationMs,

        [string[]]$Tags = @(),

        [string]$RunId = '',

        [string]$ConfigurationFingerprint = '',

        [string]$ConfigurationSource = '',

        [string]$EnvironmentName = ''
    )

    $result = New-InfraPulseResult -Status 'Unknown' -CheckName 'Execution' -Category 'Control' -ComputerName $ComputerName -Target $ComputerName -Message "The health scan for '$ComputerName' ended before a complete report was produced." -ObservedValue $false -CriticalThreshold 'Scan must complete' -Recommendation 'Review the captured error, target prerequisites, account permissions, and the selected checks. Re-run with -Verbose after correcting the underlying condition.' -Evidence ([ordered]@{ RequestedComputerName = $RequestedComputerName; ComputerName = $ComputerName; Error = $ErrorMessage }) -DurationMs $DurationMs -ErrorMessage $ErrorMessage
    return New-InfraPulseReport -RequestedComputerName $RequestedComputerName -ComputerName $ComputerName -Inventory $null -Results @($result) -DurationMs $DurationMs -Tags $Tags -RunId $RunId -ConfigurationFingerprint $ConfigurationFingerprint -ConfigurationSource $ConfigurationSource -EnvironmentName $EnvironmentName
}
