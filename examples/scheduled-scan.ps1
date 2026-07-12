[CmdletBinding()]
param(
    [string[]]$ComputerName = @('localhost'),

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.minimal.psd1'),

    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../out/scheduled')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$reports = Invoke-InfraPulse `
    -ComputerName $ComputerName `
    -ConfigurationPath $ConfigurationPath `
    -Tag 'scheduled'

$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory "infra-pulse-$timestamp.html") -Force
$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory "infra-pulse-$timestamp.json") -Force

$blocking = @($reports.Results | Where-Object Status -In 'Critical', 'Unknown')
if ($blocking.Count -gt 0) {
    $blocking | Format-Table ComputerName, Status, CheckName, Target, Message -AutoSize
    exit 2
}

exit 0
