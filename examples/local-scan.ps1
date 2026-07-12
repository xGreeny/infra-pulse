[CmdletBinding()]
param(
    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.minimal.psd1'),

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out/local-health.html')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

$report = Invoke-InfraPulse -ConfigurationPath $ConfigurationPath -Tag 'local', 'interactive'
$report | Export-InfraPulseReport -Path $OutputPath -Force

$report
$report.Results |
    Where-Object Status -NotIn 'Healthy', 'Skipped' |
    Format-Table Status, CheckName, Target, Message -AutoSize
