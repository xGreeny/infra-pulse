# Configuration reference

InfraPulse configuration is a PowerShell data file (`.psd1`) with schema version `1.0`. A file can be partial: InfraPulse deep-merges it with defaults before validation.

Generate a documented file:

```powershell
New-InfraPulseConfiguration -Path .\config\my-environment.psd1
```

Validate without contacting a target:

```powershell
$result = Test-InfraPulseConfiguration -Path .\config\my-environment.psd1
$result | Format-List Source, IsValid, Errors, Warnings
$result.EffectiveConfiguration
```

## Merge behavior

- Dictionaries are merged recursively.
- Scalar values replace defaults.
- Arrays replace defaults; they are not concatenated.
- Unknown check sections generate a warning and are not executed.
- An unsupported `SchemaVersion` is invalid.

This makes role-specific overrides concise while keeping the effective configuration complete and deterministic.

## General

| Key | Type | Default | Constraint / behavior |
|---|---|---:|---|
| `DefaultChecks` | string array | All catalog checks | Order of execution when `-Check` is omitted |
| `ContinueOnError` | Boolean | `$true` | Converts check failures to `Unknown`; `$false` rethrows |
| `ConnectionTimeoutSeconds` | number | `15` | `1`–`300`; used when InfraPulse opens WSMan sessions |
| `IncludeInventory` | Boolean | `$true` | Controls whether collected inventory is attached to reports |

Inventory is still collected internally to identify the target platform and canonical computer name.

## Disk

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `Enabled` | Boolean | `$true` | Used by default selection |
| `Include` | string array | `'*'` | Wildcards matched against drive ID |
| `Exclude` | string array | `'A:'` | Exclusions win over inclusions |
| `WarningFreePercent` | number | `20` | `0`–`100` |
| `CriticalFreePercent` | number | `10` | `0`–warning |
| `WarningFreeGB` | number | `20` | `>= 0` |
| `CriticalFreeGB` | number | `10` | `0`–warning |

## Memory

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `WarningAvailablePercent` | number | `20` | `0`–`100` |
| `CriticalAvailablePercent` | number | `10` | `0`–warning |

## Uptime

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `WarningDays` | number | `45` | `>= 0` |
| `CriticalDays` | number | `90` | `>= WarningDays` |

## PendingReboot

| Key | Type | Default | Constraint |
|---|---|---|---|
| `PendingStatus` | string | `Warning` | `Warning` or `Critical` |

## Services

`Required` is an array of dictionaries:

| Key | Type | Constraint |
|---|---|---|
| `Name` | string | Required service name |
| `ExpectedStatus` | string | `Running`, `Stopped`, or `Paused` |
| `Severity` | string | `Warning` or `Critical` |

An empty `Required` array yields one `Skipped` result.

## Certificates

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `StorePaths` | string array | Machine `My`, `WebHosting` | Each path must begin `Cert:\` |
| `WarningDays` | number | `30` | `>= 0` |
| `CriticalDays` | number | `14` | `0`–warning |
| `SubjectExcludePatterns` | string array | Empty | PowerShell wildcard patterns; no empty entries |
| `IssuerExcludePatterns` | string array | Empty | PowerShell wildcard patterns matched against the issuer; no empty entries |
| `ThumbprintExclude` | string array | Empty | Exact match |
| `RequirePrivateKey` | Boolean | `$false` | Filters inventory |
| `MinTotalLifetimeDays` | number | `0` | `>= 0`; excludes certificates whose total lifetime (`NotAfter` minus `NotBefore`) is shorter; `0` keeps every certificate |

## EventLog

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `Logs` | string array | `System`, `Application` | Empty means skipped |
| `LookbackHours` | number | `24` | `> 0`, maximum `8760` |
| `Levels` | number array | `1`, `2` | Each value `1`–`5` |
| `WarningCount` | number | `25` | `>= 0` |
| `CriticalCount` | number | `100` | `>= WarningCount` |
| `MaxEvents` | number | `500` | `1`–`50000`; a capped query cannot be reported healthy |
| `ExcludeProviders` | string array | Empty | Exact provider-name match |
| `ExcludeEventIds` | number array | Empty | Exact event-ID match |
| `IncludeMessages` | Boolean | `$false` | Adds up to five truncated sample messages |

## Dns

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `QueryType` | string | `A` | `A`, `AAAA`, `CNAME`, `MX`, `NS`, `PTR`, `SRV`, `TXT` |
| `Server` | string | Empty | Empty uses target resolver configuration; custom servers require `Resolve-DnsName` |
| `Targets` | array | Empty | Strings or dictionaries; empty means skipped |

Per-target dictionary keys are `Name` (required), `Type`, and `Server`.

## Tcp

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `TimeoutMilliseconds` | number | `3000` | `100`–`60000` |
| `Endpoints` | array | Empty | Empty means skipped |

Each endpoint requires `Host` and `Port` (`1`–`65535`). `Name` and per-endpoint `TimeoutMilliseconds` are optional.

## TimeSync

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `Enabled` | Boolean | `$false` | Disabled in default selection |
| `Servers` | string array | `time.windows.com` | No empty values |
| `TimeoutMilliseconds` | number | `3000` | `100`–`60000` |
| `WarningOffsetSeconds` | number | `2` | `>= 0` |
| `CriticalOffsetSeconds` | number | `5` | `>= warning` |

## Explicit check selection

`-Check` overrides `Enabled` and `General.DefaultChecks` for that invocation:

```powershell
Invoke-InfraPulse -Check Disk, Certificates -ConfigurationPath .\config\my-environment.psd1
```

The selected checks still use their effective configuration sections.
