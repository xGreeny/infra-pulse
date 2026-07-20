function Export-InfraPulseComparison {
    <#
    .SYNOPSIS
        Exports InfraPulse comparisons to HTML, JSON, or CSV.

    .DESCRIPTION
        Collects InfraPulse.Comparison objects from the pipeline and writes a self-contained HTML change report, a structured JSON array, or a flattened CSV dataset with one row per classified change.

    .PARAMETER InputObject
        One or more InfraPulse.Comparison objects produced by Compare-InfraPulseReport.

    .PARAMETER Path
        Destination file path.

    .PARAMETER Format
        Html, Json, or Csv. When omitted, the format is inferred from the file extension and defaults to Html.

    .PARAMETER Title
        Title used in the HTML report.

    .PARAMETER Force
        Overwrites an existing file.

    .PARAMETER PassThru
        Returns the created file.

    .EXAMPLE
        Compare-InfraPulseReport $before $after | Export-InfraPulseComparison -Path .\evidence\change-report.html -Force

    .EXAMPLE
        $comparison | Export-InfraPulseComparison -Path .\evidence\change.csv -Format Csv -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Html', 'Json', 'Csv')]
        [string]$Format,

        [ValidateNotNullOrEmpty()]
        [string]$Title = 'Infrastructure Change Report',

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        $comparisons = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -eq $InputObject.PSObject.Properties['Changes'] -or $null -eq $InputObject.PSObject.Properties['HasRegressions']) {
            throw 'InputObject is not an InfraPulse comparison.'
        }
        [void]$comparisons.Add($InputObject)
    }

    end {
        if ($comparisons.Count -eq 0) {
            throw 'No InfraPulse comparisons were supplied.'
        }

        $comparisonArray = @($comparisons.ToArray())
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not $PSBoundParameters.ContainsKey('Format')) {
            switch ([System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()) {
                '.json' { $Format = 'Json' }
                '.csv' { $Format = 'Csv' }
                default { $Format = 'Html' }
            }
        }

        if ((Test-Path -LiteralPath $resolvedPath) -and -not $Force) {
            throw "File already exists: '$resolvedPath'. Use -Force to overwrite it."
        }

        $parent = Split-Path -Path $resolvedPath -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -Path $parent -ItemType Directory -Force
        }

        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Export InfraPulse $Format comparison")) {
            return
        }

        switch ($Format) {
            'Html' {
                $content = ConvertTo-InfraPulseComparisonHtmlReport -Comparisons $comparisonArray -Title $Title
            }
            'Json' {
                $content = ConvertTo-Json -InputObject (ConvertTo-InfraPulseSerializableValue -Value $comparisonArray) -Depth 12
            }
            'Csv' {
                $rows = foreach ($comparison in $comparisonArray) {
                    foreach ($change in @($comparison.Changes)) {
                        [pscustomobject][ordered]@{
                            ComputerName            = [string]$comparison.ComputerName
                            ChangeType              = [string]$change.ChangeType
                            CheckName               = [string]$change.CheckName
                            Category                = [string]$change.Category
                            Target                  = [string]$change.Target
                            ReferenceStatus         = [string]$change.ReferenceStatus
                            DifferenceStatus        = [string]$change.DifferenceStatus
                            ReferenceObservedValue  = [string]$change.ReferenceObservedValue
                            DifferenceObservedValue = [string]$change.DifferenceObservedValue
                            ReferenceMessage        = [string]$change.ReferenceMessage
                            DifferenceMessage       = [string]$change.DifferenceMessage
                            EvidenceChanged         = [string]$change.EvidenceChanged
                        }
                    }
                }
                $content = @($rows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
            }
        }

        Write-InfraPulseUtf8File -Path $resolvedPath -Content $content
        if ($PassThru) {
            return Get-Item -LiteralPath $resolvedPath
        }
    }
}
