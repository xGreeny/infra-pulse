[CmdletBinding()]
param(
    [string]$ComputerName = 'localhost',

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.minimal.psd1'),

    [string]$PolicyPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/change-policy.example.psd1')
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

$evaluation = $report | Test-InfraPulseReport -PolicyPath $PolicyPath
if (-not $evaluation.Passed) {
    $evaluation.Blocking | Format-Table -AutoSize
    throw "InfraPulse gate failed: $($evaluation.Message)"
}

Write-Output "InfraPulse gate passed for $($report.ComputerName): $($evaluation.Message)"
