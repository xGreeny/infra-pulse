[CmdletBinding()]
param(
    [string]$ComputerName = 'localhost',

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.minimal.psd1'),

    [ValidateSet('Critical', 'Unknown', 'Warning')]
    [string[]]$BlockingStatus = @('Critical', 'Unknown')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

$report = Invoke-InfraPulse `
    -ComputerName $ComputerName `
    -ConfigurationPath $ConfigurationPath `
    -Tag 'validation-gate' `
    -FailFast

$blocking = @($report.Results | Where-Object Status -In $BlockingStatus)
if ($blocking.Count -gt 0) {
    $blocking |
        Select-Object ComputerName, Status, CheckName, Target, Message |
        Format-Table -AutoSize
    throw "InfraPulse gate failed with $($blocking.Count) blocking result(s)."
}

Write-Output "InfraPulse gate passed for $($report.ComputerName): $($report.Summary.Healthy) healthy result(s)."
