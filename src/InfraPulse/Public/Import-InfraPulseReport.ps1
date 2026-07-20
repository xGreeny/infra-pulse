function Import-InfraPulseReport {
    <#
    .SYNOPSIS
        Imports InfraPulse JSON reports as typed objects.

    .DESCRIPTION
        Reads one or more JSON files produced by Export-InfraPulseReport, validates that each entry is an InfraPulse report with a supported schema version, restores DateTime values from both ISO 8601 and legacy Windows PowerShell JSON date encodings, and rehydrates the InfraPulse.Report and InfraPulse.Result type names so imported reports behave like freshly collected ones.

        Schema 1.0 reports are upgraded in place: missing 1.1 fields such as RunId and ConfigurationFingerprint are added with empty values so downstream comparison and policy commands can rely on a stable shape.

    .PARAMETER Path
        One or more JSON report files.

    .EXAMPLE
        $report = Import-InfraPulseReport -Path .\evidence\before.json

    .EXAMPLE
        Get-ChildItem .\evidence\*.json | Import-InfraPulseReport | Test-InfraPulseReport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path
    )

    process {
        foreach ($currentPath in $Path) {
            $resolvedPath = (Resolve-Path -LiteralPath $currentPath -ErrorAction Stop).ProviderPath
            $rawContent = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($rawContent)) {
                throw "File '$resolvedPath' is empty and cannot be imported as an InfraPulse report."
            }

            try {
                $parsed = ConvertFrom-Json -InputObject $rawContent -ErrorAction Stop
            }
            catch {
                throw "File '$resolvedPath' does not contain valid JSON: $($_.Exception.Message)"
            }

            foreach ($entry in @($parsed)) {
                ConvertTo-InfraPulseImportedReport -Entry $entry -Source $resolvedPath
            }
        }
    }
}
