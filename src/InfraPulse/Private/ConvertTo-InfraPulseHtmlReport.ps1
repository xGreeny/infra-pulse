function ConvertTo-InfraPulseHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Reports,

        [Parameter(Mandatory)]
        [string]$Title
    )

    $reportArray = @($Reports)
    if ($reportArray.Count -eq 0) {
        throw 'At least one report is required to build an HTML document.'
    }

    $builder = New-Object System.Text.StringBuilder
    $allResults = @($reportArray | ForEach-Object { @($_.Results) })
    $aggregate = Get-InfraPulseSummary -Results $allResults
    $aggregateClass = Get-InfraPulseStatusCssClass -Status $aggregate.OverallStatus
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
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background: radial-gradient(circle at 15% 0%, rgba(99, 230, 190, .09), transparent 36rem), var(--bg);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.5;
}
button, input, select { font: inherit; }
main { width: min(1480px, calc(100% - 32px)); margin: 32px auto 64px; }
.hero {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 24px;
  align-items: center;
  padding: 30px;
  border: 1px solid var(--line);
  border-radius: 20px;
  background: linear-gradient(145deg, rgba(21, 31, 49, .97), rgba(10, 16, 28, .97));
  box-shadow: var(--shadow);
}
.eyebrow { color: var(--accent); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .78rem; letter-spacing: .16em; text-transform: uppercase; }
h1 { margin: 8px 0 4px; font-size: clamp(2rem, 5vw, 3.8rem); line-height: 1; letter-spacing: -.04em; }
.subtitle { margin: 12px 0 0; color: var(--muted); max-width: 760px; }
.pulse-mark { width: 220px; max-width: 25vw; }
.overall { display: inline-flex; align-items: center; gap: 8px; margin-top: 18px; padding: 8px 12px; border-radius: 999px; font-weight: 700; border: 1px solid currentColor; }
.overall::before, .status::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: currentColor; box-shadow: 0 0 14px currentColor; }
.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 12px; margin: 18px 0; }
.metric { padding: 16px 18px; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); }
.metric .value { display: block; font-size: 1.65rem; font-weight: 800; font-variant-numeric: tabular-nums; }
.metric .label { color: var(--muted); font-size: .78rem; letter-spacing: .08em; text-transform: uppercase; }
.toolbar {
  position: sticky;
  top: 0;
  z-index: 10;
  display: grid;
  grid-template-columns: minmax(220px, 1fr) auto auto auto auto;
  gap: 10px;
  align-items: center;
  margin: 18px 0 32px;
  padding: 12px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(16, 24, 39, .94);
  box-shadow: 0 10px 35px rgba(0, 0, 0, .24);
  backdrop-filter: blur(12px);
}
.control { width: 100%; min-height: 40px; padding: 9px 12px; border: 1px solid var(--line); border-radius: 9px; background: #0b1220; color: var(--text); outline: none; }
.control:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(99, 230, 190, .12); }
.button { min-height: 40px; padding: 9px 14px; border: 1px solid var(--line); border-radius: 9px; background: var(--panel-2); color: var(--text); cursor: pointer; }
.button:hover { border-color: var(--accent); }
.visible-count { color: var(--muted); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .8rem; white-space: nowrap; }
.host { margin: 28px 0; border: 1px solid var(--line); border-radius: 18px; overflow: hidden; background: var(--panel); box-shadow: var(--shadow); }
.host[hidden], tr[hidden] { display: none; }
.host-header { display: flex; justify-content: space-between; gap: 20px; align-items: center; padding: 22px 24px; background: var(--panel-2); border-bottom: 1px solid var(--line); }
.host-title { margin: 0; font-size: 1.35rem; }
.host-meta { margin-top: 4px; color: var(--muted); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .82rem; }
.tags { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
.tag { padding: 3px 8px; border: 1px solid var(--line); border-radius: 999px; color: var(--accent-2); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .72rem; }
.inventory { display: grid; grid-template-columns: repeat(4, minmax(150px, 1fr)); gap: 1px; background: var(--line); border-bottom: 1px solid var(--line); }
.inventory div { padding: 14px 18px; background: var(--panel); }
.inventory dt { margin: 0 0 4px; color: var(--muted); font-size: .72rem; letter-spacing: .08em; text-transform: uppercase; }
.inventory dd { margin: 0; font-size: .92rem; overflow-wrap: anywhere; }
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; min-width: 1140px; }
th { padding: 12px 14px; color: var(--muted); background: rgba(255,255,255,.018); border-bottom: 1px solid var(--line); text-align: left; font-size: .72rem; letter-spacing: .08em; text-transform: uppercase; }
td { padding: 14px; border-bottom: 1px solid var(--line-soft); vertical-align: top; font-size: .88rem; }
tr:last-child td { border-bottom: 0; }
tr:hover td { background: rgba(255,255,255,.018); }
.status { display: inline-flex; align-items: center; gap: 7px; padding: 4px 9px; border: 1px solid currentColor; border-radius: 999px; font-weight: 750; font-size: .75rem; white-space: nowrap; }
.healthy { color: var(--healthy); }
.warning { color: var(--warning); }
.critical { color: var(--critical); }
.unknown { color: var(--unknown); }
.skipped { color: var(--skipped); }
.mono { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .82rem; }
.muted { color: var(--muted); }
.threshold { display: block; white-space: nowrap; }
.recommendation { max-width: 380px; }
.fleet table { min-width: 720px; }
.fleet a { color: var(--accent-2); text-decoration: none; }
.fleet a:hover { text-decoration: underline; }
details { margin-top: 8px; }
summary { color: var(--accent); cursor: pointer; font-size: .78rem; }
pre { white-space: pre-wrap; word-break: break-word; max-width: 640px; padding: 12px; border: 1px solid var(--line); border-radius: 10px; background: #090e19; color: #c9d7e8; font-size: .74rem; }
.empty-state { display: none; margin: 28px 0; padding: 28px; border: 1px dashed var(--line); border-radius: 16px; color: var(--muted); text-align: center; }
footer { margin-top: 28px; color: var(--muted); text-align: center; font-size: .8rem; }
@media (max-width: 960px) {
  .hero { grid-template-columns: 1fr; }
  .pulse-mark { display: none; }
  .inventory { grid-template-columns: repeat(2, 1fr); }
  .toolbar { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 560px) {
  main { width: min(100% - 18px, 1480px); margin-top: 10px; }
  .hero { padding: 22px; }
  .inventory { grid-template-columns: 1fr; }
  .host-header { align-items: flex-start; flex-direction: column; }
  .toolbar { position: static; grid-template-columns: 1fr; }
}
@media print {
  :root { color-scheme: light; --bg: #fff; --panel: #fff; --panel-2: #f4f6f8; --line: #d9dee5; --line-soft: #e5e7eb; --text: #111827; --muted: #4b5563; --shadow: none; }
  body { background: #fff; }
  main { width: 100%; margin: 0; }
  .toolbar { display: none; }
  .host { break-inside: avoid; box-shadow: none; }
  details { display: none; }
}
'@

    $javaScript = @'
(function () {
  const queryInput = document.getElementById('filter-query');
  const statusSelect = document.getElementById('filter-status');
  const resetButton = document.getElementById('filter-reset');
  const printButton = document.getElementById('print-report');
  const visibleCount = document.getElementById('visible-count');
  const emptyState = document.getElementById('empty-state');
  const rows = Array.from(document.querySelectorAll('article.host tbody tr'));
  const hosts = Array.from(document.querySelectorAll('article.host'));

  function applyFilters() {
    const query = queryInput.value.trim().toLowerCase();
    const status = statusSelect.value;
    let shownRows = 0;
    let shownHosts = 0;

    hosts.forEach(function (host) {
      const hostMatch = !query || host.dataset.search.includes(query);
      const hostRows = Array.from(host.querySelectorAll('tbody tr'));
      let hostShownRows = 0;

      hostRows.forEach(function (row) {
        const statusMatch = status === 'all' || row.dataset.status === status;
        const textMatch = !query || hostMatch || row.dataset.search.includes(query);
        const show = statusMatch && textMatch;
        row.hidden = !show;
        if (show) {
          hostShownRows += 1;
          shownRows += 1;
        }
      });

      host.hidden = hostShownRows === 0;
      if (!host.hidden) {
        shownHosts += 1;
      }
    });

    visibleCount.textContent = shownRows + ' of ' + rows.length + ' checks | ' + shownHosts + ' hosts';
    emptyState.style.display = shownRows === 0 ? 'block' : 'none';
  }

  queryInput.addEventListener('input', applyFilters);
  statusSelect.addEventListener('change', applyFilters);
  resetButton.addEventListener('click', function () {
    queryInput.value = '';
    statusSelect.value = 'all';
    applyFilters();
    queryInput.focus();
  });
  printButton.addEventListener('click', function () { window.print(); });
  applyFilters();
}());
'@

    $null = $builder.AppendLine('<!doctype html>')
    $null = $builder.AppendLine('<html lang="en">')
    $null = $builder.AppendLine('<head>')
    $null = $builder.AppendLine('<meta charset="utf-8">')
    $null = $builder.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $null = $builder.AppendLine('<meta name="robots" content="noindex,nofollow,noarchive">')
    $null = $builder.AppendLine('<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; script-src ''unsafe-inline''; img-src data:; base-uri ''none''; form-action ''none''">')
    $null = $builder.AppendLine('<meta name="generator" content="InfraPulse ' + (ConvertTo-InfraPulseHtmlEncoded -Value $script:InfraPulseModuleVersion) + '">')
    $null = $builder.AppendLine('<title>' + (ConvertTo-InfraPulseHtmlEncoded -Value $Title) + '</title>')
    $null = $builder.AppendLine('<style>' + $css + '</style>')
    $null = $builder.AppendLine('</head>')
    $null = $builder.AppendLine('<body><main>')
    $null = $builder.AppendLine('<section class="hero">')
    $null = $builder.AppendLine('<div>')
    $null = $builder.AppendLine('<div class="eyebrow">InfraPulse // infrastructure telemetry</div>')
    $null = $builder.AppendLine('<h1>' + (ConvertTo-InfraPulseHtmlEncoded -Value $Title) + '</h1>')
    $null = $builder.AppendLine('<p class="subtitle">Read-only health telemetry for Windows infrastructure. Generated ' + $generatedAt + '.</p>')
    $null = $builder.AppendLine('<div class="overall ' + $aggregateClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $aggregate.OverallStatus) + '</div>')
    $null = $builder.AppendLine('</div>')
    $null = $builder.AppendLine('<svg class="pulse-mark" viewBox="0 0 260 100" role="img" aria-label="InfraPulse heartbeat"><defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#63e6be" stop-opacity=".15"/><stop offset=".5" stop-color="#63e6be"/><stop offset="1" stop-color="#63e6be" stop-opacity=".15"/></linearGradient></defs><path d="M5 56h42l14-28 22 58 24-72 24 54 17-28 14 16h93" fill="none" stroke="url(#g)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="129" cy="68" r="4" fill="#63e6be"/></svg>')
    $null = $builder.AppendLine('</section>')

    $metrics = [ordered]@{
        Hosts    = $reportArray.Count
        Checks   = $aggregate.Counts.Total
        Healthy  = $aggregate.Counts.Healthy
        Warning  = $aggregate.Counts.Warning
        Critical = $aggregate.Counts.Critical
        Unknown  = $aggregate.Counts.Unknown
        Skipped  = $aggregate.Counts.Skipped
    }
    $null = $builder.AppendLine('<section class="summary-grid" aria-label="Report summary">')
    foreach ($metricName in $metrics.Keys) {
        $class = switch ($metricName) {
            'Healthy' { ' healthy' }
            'Warning' { ' warning' }
            'Critical' { ' critical' }
            'Unknown' { ' unknown' }
            'Skipped' { ' skipped' }
            default { '' }
        }
        $null = $builder.AppendLine('<div class="metric' + $class + '"><span class="value">' + $metrics[$metricName] + '</span><span class="label">' + $metricName + '</span></div>')
    }
    $null = $builder.AppendLine('</section>')

    if ($reportArray.Count -ge 2) {
        $null = $builder.AppendLine('<section class="host fleet" aria-label="Fleet overview">')
        $null = $builder.AppendLine('<header class="host-header"><div><h2 class="host-title">Fleet overview</h2><div class="host-meta">' + $reportArray.Count + ' hosts</div></div><span class="status ' + $aggregateClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $aggregate.OverallStatus) + '</span></header>')
        $null = $builder.AppendLine('<div class="table-wrap"><table>')
        $null = $builder.AppendLine('<thead><tr><th>Host</th><th>Status</th><th>Critical</th><th>Warning</th><th>Unknown</th><th>Healthy</th><th>Skipped</th><th>Duration</th></tr></thead><tbody>')
        for ($fleetIndex = 0; $fleetIndex -lt $reportArray.Count; $fleetIndex++) {
            $fleetReport = $reportArray[$fleetIndex]
            $fleetClass = Get-InfraPulseStatusCssClass -Status ([string]$fleetReport.OverallStatus)
            $fleetDuration = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N0} ms', [double]$fleetReport.DurationMs)
            $null = $builder.AppendLine('<tr>')
            $null = $builder.AppendLine('<td><a class="mono" href="#host-' + $fleetIndex + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $fleetReport.ComputerName) + '</a></td>')
            $null = $builder.AppendLine('<td><span class="status ' + $fleetClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $fleetReport.OverallStatus) + '</span></td>')
            $null = $builder.AppendLine('<td class="mono">' + [int]$fleetReport.Summary.Critical + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + [int]$fleetReport.Summary.Warning + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + [int]$fleetReport.Summary.Unknown + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + [int]$fleetReport.Summary.Healthy + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + [int]$fleetReport.Summary.Skipped + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + (ConvertTo-InfraPulseHtmlEncoded -Value $fleetDuration) + '</td>')
            $null = $builder.AppendLine('</tr>')
        }
        $null = $builder.AppendLine('</tbody></table></div></section>')
    }

    $null = $builder.AppendLine('<section class="toolbar" aria-label="Report filters">')
    $null = $builder.AppendLine('<input id="filter-query" class="control" type="search" placeholder="Filter host, check, target or message" aria-label="Filter report">')
    $null = $builder.AppendLine('<select id="filter-status" class="control" aria-label="Filter by status"><option value="all">All statuses</option><option value="critical">Critical</option><option value="warning">Warning</option><option value="unknown">Unknown</option><option value="healthy">Healthy</option><option value="skipped">Skipped</option></select>')
    $null = $builder.AppendLine('<button id="filter-reset" class="button" type="button">Reset</button>')
    $null = $builder.AppendLine('<button id="print-report" class="button" type="button">Print</button>')
    $null = $builder.AppendLine('<span id="visible-count" class="visible-count" aria-live="polite"></span>')
    $null = $builder.AppendLine('</section>')

    for ($hostIndex = 0; $hostIndex -lt $reportArray.Count; $hostIndex++) {
        $report = $reportArray[$hostIndex]
        $hostClass = Get-InfraPulseStatusCssClass -Status ([string]$report.OverallStatus)
        $generated = if ($report.GeneratedAtUtc) { ([datetime]$report.GeneratedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' } else { 'n/a' }
        $duration = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N0} ms', [double]$report.DurationMs)
        $tags = @($report.Tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $inventorySearch = if ($null -eq $report.Inventory) { '' } else { ConvertTo-Json -InputObject (ConvertTo-InfraPulseSerializableValue -Value $report.Inventory) -Depth 4 -Compress }
        $hostSearch = (@([string]$report.ComputerName, [string]$report.RequestedComputerName, ($tags -join ' '), $inventorySearch) -join ' ').ToLowerInvariant()

        $null = $builder.AppendLine('<article class="host" id="host-' + $hostIndex + '" data-search="' + (ConvertTo-InfraPulseHtmlEncoded -Value $hostSearch) + '">')
        $null = $builder.AppendLine('<header class="host-header"><div><h2 class="host-title">' + (ConvertTo-InfraPulseHtmlEncoded -Value $report.ComputerName) + '</h2><div class="host-meta">generated ' + (ConvertTo-InfraPulseHtmlEncoded -Value $generated) + ' | duration ' + (ConvertTo-InfraPulseHtmlEncoded -Value $duration) + '</div>')
        if ($tags.Count -gt 0) {
            $null = $builder.AppendLine('<div class="tags">')
            foreach ($tag in $tags) {
                $null = $builder.AppendLine('<span class="tag">' + (ConvertTo-InfraPulseHtmlEncoded -Value $tag) + '</span>')
            }
            $null = $builder.AppendLine('</div>')
        }
        $null = $builder.AppendLine('</div><span class="status ' + $hostClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $report.OverallStatus) + '</span></header>')

        if ($null -ne $report.Inventory) {
            $inventoryItems = [ordered]@{
                'Operating system' = [string]$report.Inventory.OperatingSystem
                'Version / build'  = (([string]$report.Inventory.Version) + ' / ' + ([string]$report.Inventory.BuildNumber)).Trim(' ', '/')
                'Architecture'     = [string]$report.Inventory.Architecture
                'FQDN'             = [string]$report.Inventory.Fqdn
                'Manufacturer'     = [string]$report.Inventory.Manufacturer
                'Model'            = [string]$report.Inventory.Model
                'Domain'           = [string]$report.Inventory.Domain
                'PowerShell'       = (([string]$report.Inventory.PowerShellEdition) + ' ' + ([string]$report.Inventory.PowerShellVersion)).Trim()
            }
            $null = $builder.AppendLine('<dl class="inventory">')
            foreach ($itemName in $inventoryItems.Keys) {
                $value = if ([string]::IsNullOrWhiteSpace([string]$inventoryItems[$itemName])) { 'n/a' } else { [string]$inventoryItems[$itemName] }
                $null = $builder.AppendLine('<div><dt>' + (ConvertTo-InfraPulseHtmlEncoded -Value $itemName) + '</dt><dd>' + (ConvertTo-InfraPulseHtmlEncoded -Value $value) + '</dd></div>')
            }
            $null = $builder.AppendLine('</dl>')
        }

        $null = $builder.AppendLine('<div class="table-wrap"><table>')
        $null = $builder.AppendLine('<thead><tr><th>Status</th><th>Check</th><th>Target</th><th>Message</th><th>Observed</th><th>Thresholds</th><th>Recommendation / evidence</th></tr></thead><tbody>')
        foreach ($result in @($report.Results)) {
            $statusClass = Get-InfraPulseStatusCssClass -Status ([string]$result.Status)
            $observed = if ($null -eq $result.ObservedValue -or [string]::IsNullOrWhiteSpace([string]$result.ObservedValue)) { '-' } else { [string]$result.ObservedValue }
            $thresholdParts = @()
            if (-not [string]::IsNullOrWhiteSpace([string]$result.WarningThreshold)) {
                $thresholdParts += '<span class="threshold">W: ' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.WarningThreshold) + '</span>'
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.CriticalThreshold)) {
                $thresholdParts += '<span class="threshold">C: ' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.CriticalThreshold) + '</span>'
            }
            $thresholds = if ($thresholdParts.Count -eq 0) { '-' } else { $thresholdParts -join '' }
            $recommendation = if ([string]::IsNullOrWhiteSpace([string]$result.Recommendation)) { '<span class="muted">No action required.</span>' } else { ConvertTo-InfraPulseHtmlEncoded -Value $result.Recommendation }
            $evidenceJson = ConvertTo-Json -InputObject (ConvertTo-InfraPulseSerializableValue -Value $result.Evidence) -Depth 8
            $rowSearch = (@([string]$result.Status, [string]$result.CheckName, [string]$result.Category, [string]$result.Target, [string]$result.Message, [string]$result.ObservedValue, [string]$result.Recommendation, [string]$result.Error) -join ' ').ToLowerInvariant()

            $null = $builder.AppendLine('<tr data-status="' + (ConvertTo-InfraPulseHtmlEncoded -Value (([string]$result.Status).ToLowerInvariant())) + '" data-search="' + (ConvertTo-InfraPulseHtmlEncoded -Value $rowSearch) + '">')
            $null = $builder.AppendLine('<td><span class="status ' + $statusClass + '">' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.Status) + '</span></td>')
            $null = $builder.AppendLine('<td><span class="mono">' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.CheckName) + '</span><br><span class="muted">' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.Category) + '</span></td>')
            $null = $builder.AppendLine('<td>' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.Target) + '</td>')
            $null = $builder.AppendLine('<td>' + (ConvertTo-InfraPulseHtmlEncoded -Value $result.Message) + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + (ConvertTo-InfraPulseHtmlEncoded -Value $observed) + '</td>')
            $null = $builder.AppendLine('<td class="mono">' + $thresholds + '</td>')
            $null = $builder.AppendLine('<td class="recommendation">' + $recommendation + '<details><summary>Evidence</summary><pre>' + (ConvertTo-InfraPulseHtmlEncoded -Value $evidenceJson) + '</pre></details></td>')
            $null = $builder.AppendLine('</tr>')
        }
        $null = $builder.AppendLine('</tbody></table></div></article>')
    }

    $null = $builder.AppendLine('<div id="empty-state" class="empty-state">No checks match the current filters.</div>')
    $versions = @($reportArray | ForEach-Object { [string]$_.ToolVersion } | Select-Object -Unique) -join ', '
    $null = $builder.AppendLine('<footer>InfraPulse ' + (ConvertTo-InfraPulseHtmlEncoded -Value $versions) + ' | read-only infrastructure health report</footer>')
    $null = $builder.AppendLine('<script>' + $javaScript + '</script>')
    $null = $builder.AppendLine('</main></body></html>')

    return $builder.ToString()
}
