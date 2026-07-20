function Export-InfraPulseReport {
    <#
    .SYNOPSIS
        Exports InfraPulse reports to HTML, JSON, or CSV.

    .DESCRIPTION
        Collects InfraPulse.Report objects from the pipeline and writes a self-contained HTML dashboard, structured JSON array, or flattened CSV dataset.

    .PARAMETER InputObject
        One or more InfraPulse.Report objects.

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
        Invoke-InfraPulse | Export-InfraPulseReport -Path .\out\infra-pulse.html -Force

    .EXAMPLE
        $reports | Export-InfraPulseReport -Path .\out\infra-pulse.json -Format Json -Force
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
        [string]$Title = 'Infrastructure Health Report',

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        $reports = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -eq $InputObject.PSObject.Properties['Results'] -or $null -eq $InputObject.PSObject.Properties['OverallStatus']) {
            throw 'InputObject is not an InfraPulse report.'
        }
        [void]$reports.Add($InputObject)
    }

    end {
        if ($reports.Count -eq 0) {
            throw 'No InfraPulse reports were supplied.'
        }

        $reportArray = @($reports.ToArray())
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

        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Export InfraPulse $Format report")) {
            return
        }

        switch ($Format) {
            'Html' {
                $content = ConvertTo-InfraPulseHtmlReport -Reports $reportArray -Title $Title
            }
            'Json' {
                $content = ConvertTo-Json -InputObject (ConvertTo-InfraPulseSerializableValue -Value $reportArray) -Depth 12
            }
            'Csv' {
                $rows = foreach ($report in $reportArray) {
                    foreach ($result in @($report.Results)) {
                        [pscustomobject][ordered]@{
                            GeneratedAtUtc        = if ($report.GeneratedAtUtc) { ([datetime]$report.GeneratedAtUtc).ToUniversalTime().ToString('o') } else { '' }
                            ComputerName          = [string]$report.ComputerName
                            OverallStatus         = [string]$report.OverallStatus
                            CheckName             = [string]$result.CheckName
                            Category              = [string]$result.Category
                            Target                = [string]$result.Target
                            Status                = [string]$result.Status
                            Message               = [string]$result.Message
                            ObservedValue         = [string]$result.ObservedValue
                            WarningThreshold      = [string]$result.WarningThreshold
                            CriticalThreshold     = [string]$result.CriticalThreshold
                            Recommendation        = [string]$result.Recommendation
                            CheckDurationMs       = [double]$result.DurationMs
                            Error                 = [string]$result.Error
                            EvidenceJson          = ConvertTo-Json -InputObject (ConvertTo-InfraPulseSerializableValue -Value $result.Evidence) -Depth 8 -Compress
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
