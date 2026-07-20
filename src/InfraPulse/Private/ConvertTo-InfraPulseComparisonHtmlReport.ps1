function ConvertTo-InfraPulseComparisonHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Comparisons,

        [Parameter(Mandatory)]
        [string]$Title
    )

    $comparisonArray = @($Comparisons)
    if ($comparisonArray.Count -eq 0) {
        throw 'At least one comparison is required to build an HTML document.'
    }

    $totals = [ordered]@{
        NewFinding    = 0
        Regressed     = 0
        Resolved      = 0
        Improved      = 0
        Changed       = 0
        NotComparable = 0
        Added         = 0
        Unchanged     = 0
    }
    foreach ($comparison in $comparisonArray) {
        foreach ($changeTypeName in @($totals.Keys)) {
            $totals[$changeTypeName] = [int]$totals[$changeTypeName] + [int]$comparison.Summary.$changeTypeName
        }
    }
    $hasRegressions = @($comparisonArray | Where-Object { [bool]$_.HasRegressions }).Count -gt 0
    $verdictClass = if ($hasRegressions) { 'critical' } else { 'healthy' }
    $verdictText = if ($hasRegressions) {
        '{0} regression(s) detected' -f ([int]$totals.NewFinding + [int]$totals.Regressed)
    }
    else {
        'No regressions detected'
    }
    $generatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'

    $css = @'
:root {
  color-scheme: dark;
  --bg: #080c16;
  --panel: #101827;
  --panel-2: #151f31;
  --line: #26334a;
  --line-soft: rgba(38, 51, 74, .72);
  --text: #edf4ff;
  --muted: #9fb0c7;
  --accent: #63e6be;
  --accent-2: #78a9ff;
  --healthy: #45d483;
  --warning: #f7c948;
  --critical: #ff6b6b;
  --unknown: #8aa4c8;
  --skipped: #66758a;
  --shadow: 0 18px 55px rgba(0, 0, 0, .28);
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: radial-gradient(circle at 15% 0%, rgba(99, 230, 190, .09), transparent 36rem), var(--bg);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.5;
}
main { width: min(1480px, calc(100% - 32px)); margin: 32px auto 64px; }
.hero {
  padding: 30px;
  border: 1px solid var(--line);
  border-radius: 20px;
  background: linear-gradient(145deg, rgba(21, 31, 49, .97), rgba(10, 16, 28, .97));
  box-shadow: var(--shadow);
}
.eyebrow { color: var(--accent); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .78rem; letter-spacing: .16em; text-transform: uppercase; }
h1 { margin: 8px 0 4px; font-size: clamp(2rem, 5vw, 3.4rem); line-height: 1; letter-spacing: -.04em; }
.subtitle { margin: 12px 0 0; color: var(--muted); max-width: 760px; }
.verdict { display: inline-flex; align-items: center; gap: 8px; margin-top: 18px; padding: 8px 12px; border-radius: 999px; font-weight: 700; border: 1px solid currentColor; }
.verdict::before, .status::before, .change::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: currentColor; box-shadow: 0 0 14px currentColor; }
.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; margin: 18px 0; }
.metric { padding: 16px 18px; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); }
.metric .value { display: block; font-size: 1.65rem; font-weight: 800; font-variant-numeric: tabular-nums; }
.metric .label { color: var(--muted); font-size: .74rem; letter-spacing: .06em; text-transform: uppercase; }
.host { margin: 28px 0; border: 1px solid var(--line); border-radius: 18px; overflow: hidden; background: var(--panel); box-shadow: var(--shadow); }
.host-header { display: flex; justify-content: space-between; gap: 20px; align-items: center; padding: 22px 24px; background: var(--panel-2); border-bottom: 1px solid var(--line); }
.host-title { margin: 0; font-size: 1.35rem; }
.host-meta { margin-top: 4px; color: var(--muted); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .82rem; }
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; min-width: 1080px; }
th { padding: 12px 14px; color: var(--muted); background: rgba(255,255,255,.018); border-bottom: 1px solid var(--line); text-align: left; font-size: .72rem; letter-spacing: .08em; text-transform: uppercase; }
td { padding: 14px; border-bottom: 1px solid var(--line-soft); vertical-align: top; font-size: .88rem; }
tr:last-child td { border-bottom: 0; }
.status, .change { display: inline-flex; align-items: center; gap: 7px; padding: 4px 9px; border: 1px solid currentColor; border-radius: 999px; font-weight: 750; font-size: .75rem; white-space: nowrap; }
.healthy { color: var(--healthy); }
.warning { color: var(--warning); }
.critical { color: var(--critical); }
.unknown { color: var(--unknown); }
.skipped { color: var(--skipped); }
.accent { color: var(--accent); }
.accent-2 { color: var(--accent-2); }
.muted { color: var(--muted); }
.mono { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .82rem; }
.message { max-width: 420px; }
footer { margin-top: 28px; color: var(--muted); text-align: center; font-size: .8rem; }
@media print {
  :root { color-scheme: light; --bg: #fff; --panel: #fff; --panel-2: #f4f6f8; --line: #d9dee5; --line-soft: #e5e7eb; --text: #111827; --muted: #4b5563; --shadow: none; }
  body { background: #fff; }
  main { width: 100%; margin: 0; }
  .host { break-inside: avoid; box-shadow: none; }
}
'@

    $builder = New-Object System.Text.StringBuilder
    $null = $builder.AppendLine('<!doctype html>')
    $null = $builder.AppendLine('<html lang="en">')
    $null = $builder.AppendLine('<head>')
    $null = $builder.AppendLine('<meta charset="utf-8">')
    $null = $builder.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $null = $builder.AppendLine('<meta name="robots" content="noindex,nofollow,noarchive">')
    $null = $builder.AppendLine('<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; img-src data:; base-uri ''none''; form-action ''none''">')
    $null = $builder.AppendLine('<meta name="generator" content="InfraPulse ' + (ConvertTo-InfraPulseHtmlEncoded -Value $script:InfraPulseModuleVersion) + '">')
    $null = $builder.AppendLine('<title>' + (ConvertTo-InfraPulseHtmlEncoded -Value $Title) + '</title>')
    $null = $builder.AppendLine('<style>' + $css + '</style>')
    $null = $builder.AppendLine('</head>')
    $null = $builder.AppendLine('<body><main>')
    $null = $builder.AppendLine('<section class="hero">')
    $null = $builder.AppendLine('<div class="eyebrow">InfraPulse // change evidence</div>')
    $null = $builder.AppendLine('<h1>' + (ConvertTo-InfraPulseHtmlEncoded -Value $Title) + '</h1>')
    $null = $builder.AppendLine('<p class="subtitle">Classified differences between two InfraPulse snapshots. Generated ' + $generatedAt + '.</p>')
    $null = $builder.AppendLine('<div class="verdict ' + $verdictClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $verdictText) + '</div>')
    $null = $builder.AppendLine('</section>')

    $metricClasses = @{
        NewFinding    = ' critical'
        Regressed     = ' critical'
        Resolved      = ' healthy'
        Improved      = ' accent'
        Changed       = ' warning'
        NotComparable = ' skipped'
        Added         = ' accent-2'
        Unchanged     = ''
    }
    $null = $builder.AppendLine('<section class="summary-grid" aria-label="Change summary">')
    foreach ($changeTypeName in $totals.Keys) {
        $null = $builder.AppendLine('<div class="metric' + $metricClasses[$changeTypeName] + '"><span class="value">' + [int]$totals[$changeTypeName] + '</span><span class="label">' + $changeTypeName + '</span></div>')
    }
    $null = $builder.AppendLine('</section>')

    foreach ($comparison in $comparisonArray) {
        $hostVerdictClass = if ([bool]$comparison.HasRegressions) { 'critical' } else { 'healthy' }
        $hostVerdictText = if ([bool]$comparison.HasRegressions) { 'Regressions' } else { 'No regressions' }
        $metaParts = @()
        if ($null -ne $comparison.Reference -and $null -ne $comparison.Reference.GeneratedAtUtc) {
            $metaParts += 'before ' + ([datetime]$comparison.Reference.GeneratedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
        }
        if ($null -ne $comparison.Difference -and $null -ne $comparison.Difference.GeneratedAtUtc) {
            $metaParts += 'after ' + ([datetime]$comparison.Difference.GeneratedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
        }
        if ($null -eq $comparison.ConfigurationMatches) {
            $metaParts += 'configuration match unknown'
        }
        elseif ([bool]$comparison.ConfigurationMatches) {
            $metaParts += 'same configuration'
        }
        else {
            $metaParts += 'DIFFERENT configuration'
        }

        $null = $builder.AppendLine('<article class="host">')
        $null = $builder.AppendLine('<header class="host-header"><div><h2 class="host-title">' + (ConvertTo-InfraPulseHtmlEncoded -Value $comparison.ComputerName) + '</h2><div class="host-meta">' + (ConvertTo-InfraPulseHtmlEncoded -Value ($metaParts -join ' | ')) + '</div></div><span class="status ' + $hostVerdictClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $hostVerdictText) + '</span></header>')
        $null = $builder.AppendLine('<div class="table-wrap"><table>')
        $null = $builder.AppendLine('<thead><tr><th>Change</th><th>Check</th><th>Target</th><th>Before</th><th>After</th><th>Observed</th><th>Message</th></tr></thead><tbody>')

        foreach ($change in @($comparison.Changes)) {
            $changeClass = switch ([string]$change.ChangeType) {
                'NewFinding' { 'critical' }
                'Regressed' { 'critical' }
                'Resolved' { 'healthy' }
                'Improved' { 'accent' }
                'Changed' { 'warning' }
                'NotComparable' { 'skipped' }
                'Added' { 'accent-2' }
                default { 'muted' }
            }
            $beforeStatus = if ([string]::IsNullOrWhiteSpace([string]$change.ReferenceStatus)) { '<span class="muted">-</span>' } else { '<span class="status ' + (Get-InfraPulseStatusCssClass -Status ([string]$change.ReferenceStatus)) + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.ReferenceStatus) + '</span>' }
            $afterStatus = if ([string]::IsNullOrWhiteSpace([string]$change.DifferenceStatus)) { '<span class="muted">-</span>' } else { '<span class="status ' + (Get-InfraPulseStatusCssClass -Status ([string]$change.DifferenceStatus)) + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.DifferenceStatus) + '</span>' }
            $observedBefore = if ([string]::IsNullOrWhiteSpace([string]$change.ReferenceObservedValue)) { '-' } else { [string]$change.ReferenceObservedValue }
            $observedAfter = if ([string]::IsNullOrWhiteSpace([string]$change.DifferenceObservedValue)) { '-' } else { [string]$change.DifferenceObservedValue }
            $message = if (-not [string]::IsNullOrWhiteSpace([string]$change.DifferenceMessage)) { [string]$change.DifferenceMessage } else { [string]$change.ReferenceMessage }

            $null = $builder.AppendLine('<tr>')
            $null = $builder.AppendLine('<td><span class="change ' + $changeClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.ChangeType) + '</span></td>')
            $null = $builder.AppendLine('<td><span class="mono">' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.CheckName) + '</span><br><span class="muted">' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.Category) + '</span></td>')
            $null = $builder.AppendLine('<td>' + (ConvertTo-InfraPulseHtmlEncoded -Value $change.Target) + '</td>')
            $null = $builder.AppendLine('<td>' + $beforeStatus + '</td>')
            $null = $builder.AppendLine('<td>' + $afterStatus + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + (ConvertTo-InfraPulseHtmlEncoded -Value $observedBefore) + ' &#8594; ' + (ConvertTo-InfraPulseHtmlEncoded -Value $observedAfter) + '</td>')
            $null = $builder.AppendLine('<td class="message">' + (ConvertTo-InfraPulseHtmlEncoded -Value $message) + '</td>')
            $null = $builder.AppendLine('</tr>')
        }

        $null = $builder.AppendLine('</tbody></table></div></article>')
    }

    $null = $builder.AppendLine('<footer>InfraPulse ' + (ConvertTo-InfraPulseHtmlEncoded -Value $script:InfraPulseModuleVersion) + ' | read-only change evidence report</footer>')
    $null = $builder.AppendLine('</main></body></html>')

    return $builder.ToString()
}
