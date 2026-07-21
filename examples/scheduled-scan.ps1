[CmdletBinding()]
param(
    [string[]]$ComputerName = @('localhost'),

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.minimal.psd1'),

    [string]$PolicyPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/change-policy.example.psd1'),

    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../out/scheduled'),

    [int]$KeepRuns = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

# The newest previous JSON snapshot becomes the comparison baseline.
$previousSnapshot = Get-ChildItem -Path $OutputDirectory -Filter 'infra-pulse-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object -Property Name -Descending |
    Select-Object -First 1

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$reports = Invoke-InfraPulse `
    -ComputerName $ComputerName `
    -ConfigurationPath $ConfigurationPath `
    -Tag 'scheduled'

$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory "infra-pulse-$timestamp.html") -Force
$reports | Export-InfraPulseReport -Path (Join-Path $OutputDirectory "infra-pulse-$timestamp.json") -Force

# Retention: keep the newest runs, drop older HTML/JSON pairs.
$obsolete = Get-ChildItem -Path $OutputDirectory -Filter 'infra-pulse-*.json' -File |
    Sort-Object -Property Name -Descending |
    Select-Object -Skip $KeepRuns
foreach ($file in @($obsolete)) {
    Remove-Item -LiteralPath $file.FullName -Force
    $htmlSibling = [System.IO.Path]::ChangeExtension($file.FullName, '.html')
    if (Test-Path -LiteralPath $htmlSibling) {
        Remove-Item -LiteralPath $htmlSibling -Force
    }
}

$exitCode = 0

$policyEvaluation = $reports | Test-InfraPulseReport -PolicyPath $PolicyPath
if (-not $policyEvaluation.Passed) {
    Write-Warning "Policy gate failed: $($policyEvaluation.Message)"
    $policyEvaluation.Blocking | Format-Table -AutoSize
    $exitCode = 2
}

if ($null -ne $previousSnapshot) {
    $baseline = Import-InfraPulseReport -Path $previousSnapshot.FullName
    $comparison = Compare-InfraPulseReport -ReferenceObject $baseline -DifferenceObject $reports
    $comparison | Export-InfraPulseComparison -Path (Join-Path $OutputDirectory "infra-pulse-$timestamp-changes.html") -Force

    $comparisonEvaluation = $comparison | Test-InfraPulseComparison
    if (-not $comparisonEvaluation.Passed) {
        Write-Warning "Regression gate failed against $($previousSnapshot.Name): $($comparisonEvaluation.Message)"
        $comparisonEvaluation.Violations | Format-Table -AutoSize
        if ($exitCode -eq 0) {
            $exitCode = 3
        }
    }
}

exit $exitCode
