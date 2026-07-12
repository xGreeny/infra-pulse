[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../examples')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $repositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
$fixturePath = Join-Path -Path $repositoryRoot -ChildPath 'tests/Fixtures/sample-reports.json'
Import-Module -Name $modulePath -Force

$reports = @(Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json)
$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory 'sample-report.html') -Force
$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory 'sample-report.json') -Force
$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory 'sample-report.csv') -Force
