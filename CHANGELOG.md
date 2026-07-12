# Changelog

All notable changes to InfraPulse are documented in this file. The project follows [Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/xGreeny/infra-pulse/releases/tag/v1.0.0
