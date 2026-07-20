# Report schema

InfraPulse returns PowerShell custom objects with ordered properties and explicit type names. The current schema version is `1.1`. Schema `1.0` JSON reports remain importable through `Import-InfraPulseReport`.

## `InfraPulse.Report`

| Property | Type | Description |
|---|---|---|
| `SchemaVersion` | string | Report contract version |
| `Tool` | string | Always `InfraPulse` |
| `ToolVersion` | version/string | Module version from the manifest |
| `RunId` | string | GUID shared by every report of one `Invoke-InfraPulse` invocation (1.1) |
| `RequestedComputerName` | string | Operator-supplied target name |
| `ComputerName` | string | Canonical target name when inventory succeeds |
| `GeneratedAtUtc` | DateTime | UTC report creation time |
| `StartedAtUtc` | DateTime | UTC target scan start time (1.1) |
| `CompletedAtUtc` | DateTime | UTC target scan completion time (1.1) |
| `ConfigurationFingerprint` | string | SHA-256 fingerprint of the effective configuration (1.1) |
| `OverallStatus` | string | Highest-precedence result status |
| `Summary` | object | Counts for Total, Healthy, Warning, Critical, Unknown, Skipped |
| `Inventory` | object/null | Host inventory when enabled and available |
| `Results` | array | `InfraPulse.Result` objects |
| `Tags` | string array | Normalized operator-supplied tags |
| `DurationMs` | double | Total target scan duration |

Example:

```json
{
  "SchemaVersion": "1.1",
  "Tool": "InfraPulse",
  "ToolVersion": "1.1.0",
  "RunId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "RequestedComputerName": "srv-app-01",
  "ComputerName": "SRV-APP-01",
  "GeneratedAtUtc": "2026-07-20T09:30:02.1234567Z",
  "StartedAtUtc": "2026-07-20T09:30:01.2812345Z",
  "CompletedAtUtc": "2026-07-20T09:30:02.1234567Z",
  "ConfigurationFingerprint": "0f1e2d3c4b5a69788796a5b4c3d2e1f0f1e2d3c4b5a69788796a5b4c3d2e1f0f",
  "OverallStatus": "Warning",
  "Summary": {
    "Total": 8,
    "Healthy": 6,
    "Warning": 1,
    "Critical": 0,
    "Unknown": 0,
    "Skipped": 1
  },
  "Inventory": {},
  "Results": [],
  "Tags": ["production", "pre-change"],
  "DurationMs": 842.17
}
```

The configuration fingerprint is a SHA-256 hash over a canonical, sorted-key rendering of the effective configuration. Two reports carry the same fingerprint exactly when their effective configurations are logically identical, regardless of the PowerShell edition that produced them. `Compare-InfraPulseReport` surfaces the fingerprint match so evidence collected under different policies is not treated as equivalent.

## Inventory object

| Property | Description |
|---|---|
| `ComputerName` | Target machine name |
| `Fqdn` | Resolved fully qualified domain name |
| `Platform` | `Windows` or cross-platform OS description |
| `OperatingSystem` | OS caption/description |
| `OperatingSystemSku` | Windows SKU when available |
| `Version` | OS version |
| `BuildNumber` | Windows build number when available |
| `Architecture` | OS architecture |
| `Manufacturer` | Computer-system manufacturer |
| `Model` | Computer-system model |
| `Domain` | Windows domain/workgroup value |
| `PartOfDomain` | Domain membership Boolean |
| `PowerShellVersion` | Target engine version |
| `PowerShellEdition` | Desktop or Core |
| `CollectedAtUtc` | UTC collection time |

## `InfraPulse.Result`

| Property | Type | Description |
|---|---|---|
| `SchemaVersion` | string | Result contract version |
| `ComputerName` | string | Evaluated host |
| `CheckName` | string | Catalog check or control stage |
| `Category` | string | Capacity, Lifecycle, Availability, Security, Reliability, Connectivity, or Control |
| `Target` | string | Evaluated resource such as `C:`, service, log, name, or endpoint |
| `Status` | string | Healthy, Warning, Critical, Unknown, or Skipped |
| `Message` | string | Human-readable observation |
| `ObservedValue` | object/null | Concise value suited to automation or display |
| `WarningThreshold` | object/null | Effective warning condition |
| `CriticalThreshold` | object/null | Effective critical condition |
| `Recommendation` | string | Non-remediating next action |
| `Evidence` | dictionary | Check-specific structured detail |
| `TimestampUtc` | DateTime | UTC result creation time |
| `DurationMs` | double | Check/result collection duration |
| `Error` | string | Original error message when collection failed |

## Timestamp serialization

In-memory report objects carry real `DateTime` values. When a report is exported (JSON, CSV, or the HTML evidence blocks), every `DateTime` is converted to a round-trip ISO 8601 UTC string (`yyyy-MM-ddTHH:mm:ss.fffffffZ`, .NET format specifier `o`), for example `2026-07-11T09:30:00.0000000Z`.

This applies recursively to all timestamp-bearing fields, including `GeneratedAtUtc`, `TimestampUtc`, `Inventory.CollectedAtUtc`, and evidence keys such as `LastBootTime`, `NotBefore`, `NotAfter`, and `TimeCreated`. The normalization guarantees identical output on Windows PowerShell 5.1 and PowerShell 7; without it, `ConvertTo-Json` on PowerShell 5.1 would emit the legacy `\/Date(<epoch-ms>)\/` form.

## Status aggregation

The first status with a non-zero count wins:

1. Critical
2. Warning
3. Unknown
4. Healthy
5. Skipped

Skipped results count toward `Summary.Total` but do not reduce the status of healthy checks.

## CSV mapping

CSV export writes one row per result and repeats report-level context. `Evidence` is serialized into the `EvidenceJson` column because arbitrary nested structures cannot be represented safely as flat columns.

## `InfraPulse.Comparison`

`Compare-InfraPulseReport` returns one comparison per computer name:

| Property | Type | Description |
|---|---|---|
| `SchemaVersion` | string | Comparison contract version (`1.1`) |
| `ComputerName` | string | Compared host |
| `Comparable` | Boolean | Both snapshots contained this host |
| `ConfigurationMatches` | Boolean/null | Fingerprints equal; `null` when either side lacks one |
| `HasRegressions` | Boolean | `NewFinding` + `Regressed` counts are greater than zero |
| `Reference` / `Difference` | object/null | `RunId`, `GeneratedAtUtc`, `OverallStatus`, `ConfigurationFingerprint` per side |
| `Summary` | object | Counts per change type plus `Total` |
| `Changes` | array | `InfraPulse.ResultChange` objects |

Each `InfraPulse.ResultChange` carries `ChangeType` (`NewFinding`, `Regressed`, `Resolved`, `Improved`, `Changed`, `NotComparable`, `Added`, `Unchanged`), the check identity, both statuses, both observed values, both messages, and an `EvidenceChanged` flag. Volatile evidence keys (timing values, event samples) are excluded from the change decision.

## `InfraPulse.PolicyEvaluation`

`Test-InfraPulseReport` returns:

| Property | Type | Description |
|---|---|---|
| `Passed` | Boolean | Policy satisfied |
| `Message` | string | Human-readable outcome summary |
| `PolicySource` | string | Policy file path or `Inline parameters` |
| `FailOn` | string array | Blocking statuses |
| `MaximumWarnings` | int | Warning budget |
| `TotalResults` / `EvaluatedCount` / `IgnoredCount` | int | Result accounting |
| `BlockingCount` / `WarningCount` | int | Violation counts |
| `Blocking` | array | Compact blocking-result descriptions |
| `ComputerNames` | string array | Evaluated hosts |
| `GeneratedAtUtc` | DateTime | UTC evaluation time |

## Import and rehydration

`Import-InfraPulseReport` validates that a JSON document is an InfraPulse report with schema `1.0` or `1.1`, restores DateTime values from ISO 8601 and from the legacy `\/Date(<epoch-ms>)\/` encoding that Windows PowerShell 5.1 produced before schema 1.1, reinstates the `InfraPulse.Report` and `InfraPulse.Result` type names, and adds empty `RunId`, `StartedAtUtc`, `CompletedAtUtc`, and `ConfigurationFingerprint` values to schema `1.0` reports.

## Schema evolution

Backward-compatible additions can remain in schema `1.x`. Renaming/removing properties, changing status semantics, or changing evidence types in a way that breaks consumers requires a new schema version and migration notes.
