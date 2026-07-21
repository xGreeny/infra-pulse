# Changelog

All notable changes to InfraPulse are documented in this file. The project follows [Semantic Versioning](https://semver.org/).

## [1.4.1] - 2026-07-21

### Fixed

- Truncated event-log queries that already meet a warning or critical threshold now report the count as a lower bound ("At least N ... (collection capped at MaxEvents)", observed value `N+`) instead of presenting the capped number as an exact count.

## [1.4.0] - 2026-07-21

### Added

- Parallel multi-host scans: multiple `-ComputerName` targets run in parallel runspaces with a configurable `-ThrottleLimit` (default 8); `-FailFast` and `-ThrottleLimit 1` force sequential processing, and reports are emitted in input order with one shared `RunId`.
- Fleet overview in HTML reports: a host-by-status matrix with per-host counts and anchors, shown for reports covering two or more hosts.
- Configuration discovery: without explicit parameters, `Invoke-InfraPulse` uses the `INFRAPULSE_CONFIG` environment variable or an `infra-pulse.psd1` in the working directory before falling back to built-in defaults.
- Report schema 1.2 with `ConfigurationSource`, recording the origin of the effective configuration; `Import-InfraPulseReport` accepts schemas 1.0 through 1.2.
- `PatchAge` check: days since the most recent installed Windows update, with the latest KB and recent update history as evidence.
- `Test-InfraPulseComparison`: a regression gate over `Compare-InfraPulseReport` output that blocks on `NewFinding` and `Regressed` changes by default.
- PowerShell Gallery publishing instructions in the operator documentation.

### Changed

- The scheduled-scan example now keeps a report history with retention, compares each run against the previous snapshot, and gates on both the change policy and regressions with distinct exit codes.
- HTML report durations are formatted culture-invariantly, and event-log sample levels use invariant names instead of localized display strings.

## [1.3.0] - 2026-07-21

### Added

- `Checks.PendingReboot.ExcludeReasons`: PowerShell wildcard patterns for reboot indicators that should not set the pending state, for example pending file renames that agents re-create continuously on multi-session hosts. Excluded indicators remain visible in the result evidence under `ExcludedReasons`, and a host whose only indicators are excluded reports `Healthy`.

## [1.2.0] - 2026-07-20

### Added

- `Checks.Certificates.TreatShortLivedAsRotating` (default `$true`): certificates whose total lifetime is at or below `WarningDays` can never satisfy the expiry policy by construction and are now classified as auto-rotating.

### Changed

- Auto-rotating short-lived certificates (for example Entra ID P2P device certificates) stay visible as `Healthy` results with `Rotating` and `TotalLifetimeDays` evidence while valid, and turn `Critical` only when they expire — the signal that the automatic rotation stopped. Explicit exclusions (`IssuerExcludePatterns`, `MinTotalLifetimeDays`, `SubjectExcludePatterns`, `ThumbprintExclude`) keep taking precedence.
- The certificate inventory summary now reports certificates that "satisfy the expiry policy" and includes a `RotatingCertificates` count.

## [1.1.1] - 2026-07-20

### Fixed

- The DNS check no longer misreports CNAME-chained lookups as critical resolution failures on local scans: answer properties are now probed StrictMode-safely instead of being read from record types that do not carry them.
- The TLS check now offers TLS 1.0–1.2 explicitly on Windows PowerShell 5.1 targets instead of the .NET Framework SSL3/TLS 1.0 default, which modern endpoints reject with transport errors; PowerShell 7 targets keep following operating-system defaults including TLS 1.3.

## [1.1.0] - 2026-07-20

### Added

- Report schema 1.1 with run identifiers, UTC start/completion timestamps, and effective-configuration SHA-256 fingerprints.
- `Import-InfraPulseReport` for validated JSON import and type rehydration of schema 1.0 and 1.1 reports.
- `Compare-InfraPulseReport` with regression, resolution, improvement, evidence-change, and comparability classification.
- `Export-InfraPulseComparison` for self-contained HTML, JSON, and CSV change evidence.
- `Test-InfraPulseReport` with blocking statuses, warning budgets, wildcard ignore rules, Boolean output, and opt-in terminating errors.
- Cross-platform TLS endpoint check for handshake, SNI identity, chain trust, certificate expiry, protocol, and timing evidence.
- Certificate check exclusions for auto-rotated certificates: `IssuerExcludePatterns` and `MinTotalLifetimeDays`.
- Linux PowerShell 7 CI and JaCoCo coverage output.

### Changed

- Exported timestamps are normalized to round-trip ISO 8601 UTC strings across PowerShell editions.
- Disk thresholds are evaluated against unrounded values while reports retain rounded display values.
- Service query failures remain `Unknown` instead of being misclassified as missing services.
- Missing configured certificate stores produce explicit `Unknown` results.
- Event-log collection reads one record beyond the configured cap to distinguish a full result set from truncation.
- The build resolves Pester and PSScriptAnalyzer as same-major version ranges and imports Pester before analysis, making CI resilient to preinstalled module versions.
- Build validation and module-surface tests cover all new public commands.

## [1.0.0] - 2026-07-11

### Added

- Ten read-only checks: Disk, Memory, Uptime, PendingReboot, Services, Certificates, EventLog, DNS, TCP, and TimeSync.
- Local execution, temporary WSMan sessions, and caller-owned PSSession support.
- Validated partial configuration files with deterministic default merging.
- Structured `InfraPulse.Report` and `InfraPulse.Result` object contracts.
- Self-contained, searchable HTML reports and JSON/CSV exports.
- Friendly control results for connection, inventory, and check-level failures.
- Windows PowerShell 5.1 and PowerShell 7 compatibility.
- Pester test suite, PSScriptAnalyzer policy, dual-engine CI, and tagged-release packaging.
- Operator documentation, examples, issue forms, security policy, and contribution workflow.

[1.4.1]: https://github.com/xGreeny/infra-pulse/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/xGreeny/infra-pulse/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/xGreeny/infra-pulse/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/xGreeny/infra-pulse/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/xGreeny/infra-pulse/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/xGreeny/infra-pulse/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/xGreeny/infra-pulse/releases/tag/v1.0.0
