[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.example.psd1'),

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out/remote-health.html'),

    [switch]$UseSSL
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

$credential = Get-Credential -Message 'Credential for the target PowerShell remoting endpoints'
$reports = Invoke-InfraPulse `
    -ComputerName $ComputerName `
    -Credential $credential `
    -UseSSL:$UseSSL `
    -ConfigurationPath $ConfigurationPath `
    -Tag 'remote', 'operator-run'

$reports | Export-InfraPulseReport -Path $OutputPath -Force
$reports | Sort-Object OverallStatus, ComputerName
