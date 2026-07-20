[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ComputerName,

    [string]$ConfigurationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/infra-pulse.example.psd1'),

    [Parameter(Mandatory)]
    [ValidateSet('Before', 'After')]
    [string]$Phase,

    [string]$EvidencePath = (Join-Path -Path $PSScriptRoot -ChildPath '../out/evidence')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/InfraPulse/InfraPulse.psd1'
Import-Module -Name $modulePath -Force

if (-not (Test-Path -LiteralPath $EvidencePath)) {
    $null = New-Item -Path $EvidencePath -ItemType Directory -Force
}

$beforePath = Join-Path -Path $EvidencePath -ChildPath "$ComputerName-before.json"
$afterPath = Join-Path -Path $EvidencePath -ChildPath "$ComputerName-after.json"

$report = Invoke-InfraPulse `
    -ComputerName $ComputerName `
    -ConfigurationPath $ConfigurationPath `
    -Tag 'change-validation', $Phase.ToLowerInvariant()

if ($Phase -eq 'Before') {
    $report | Export-InfraPulseReport -Path $beforePath -Force
    Write-Output "Pre-change snapshot saved to $beforePath. Re-run with -Phase After once the change is complete."
    return
}

$report | Export-InfraPulseReport -Path $afterPath -Force

$before = Import-InfraPulseReport -Path $beforePath
$comparison = Compare-InfraPulseReport -ReferenceObject $before -DifferenceObject $report

$comparisonHtml = Join-Path -Path $EvidencePath -ChildPath "$ComputerName-change-report.html"
$comparison | Export-InfraPulseComparison -Path $comparisonHtml -Force
Write-Output "Change evidence written to $comparisonHtml."

if ($comparison.HasRegressions) {
    $comparison.Changes |
        Where-Object { $_.ChangeType -in @('NewFinding', 'Regressed') } |
        Format-Table ChangeType, CheckName, Target, ReferenceStatus, DifferenceStatus -AutoSize
    throw "Post-change validation found $($comparison.Summary.NewFinding + $comparison.Summary.Regressed) regression(s) on $ComputerName."
}

Write-Output "No regressions detected on $ComputerName."
