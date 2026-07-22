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

## Configuration discovery

When `Invoke-InfraPulse` is called without `-ConfigurationPath` and `-Configuration`, it discovers a configuration in this order:

1. The file referenced by the `INFRAPULSE_CONFIG` environment variable. A set variable that points to a missing file is an error, not a silent fallback.
2. An `infra-pulse.psd1` file in the current working directory.
3. The built-in defaults.

Every report records the effective origin in `ConfigurationSource`, and the `ConfigurationFingerprint` makes configuration drift between runs detectable regardless of the source.

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
| `EnvironmentName` | string | Empty | Label for the scanned environment or customer; recorded in every report and shown in the HTML output |

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
| `Volumes` | array | Empty | Per-volume threshold overrides; each entry requires `DeviceId` (wildcards supported), every threshold key is optional and falls back to the global value |

```powershell
Disk = @{
    WarningFreePercent = 20
    Volumes = @(
        # A large data volume where 20% would flag despite ample space:
        @{ DeviceId = 'D:'; WarningFreePercent = 10; CriticalFreePercent = 5 }
    )
}
```

## Memory

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `WarningAvailablePercent` | number | `20` | `0`–`100` |
| `CriticalAvailablePercent` | number | `10` | `0`–warning |
| `WarningCommitPercent` | number | `90` | `0`–`100`; commit charge relative to the commit limit |
| `CriticalCommitPercent` | number | `95` | warning–`100` |

## Cpu

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `SampleCount` | number | `3` | `1`–`10` |
| `SampleIntervalSeconds` | number | `1` | `1`–`30` |
| `WarningPercent` | number | `85` | `0`–`100` |
| `CriticalPercent` | number | `95` | `>= WarningPercent` |

## ScheduledTasks

| Key | Type | Default | Constraint / behavior |
|---|---|---|---|
| `IncludePaths` | string array | `'\*'` | Wildcards matched against the task path |
| `ExcludePaths` | string array | `'\Microsoft\*'` | Exclusions win over inclusions |
| `ExcludeTasks` | string array | Empty | Wildcards matched against the task name |
| `ExcludeResults` | number array | `267009`, `267011` | Result codes that never count as failures |
| `WarningCount` | number | `1` | `>= 0` |
| `CriticalCount` | number | `5` | `>= WarningCount` |

## Defender

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `SignatureWarningDays` | number | `3` | `>= 0` |
| `SignatureCriticalDays` | number | `7` | `>= SignatureWarningDays` |

## Stability

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `LookbackDays` | number | `7` | `1`–`365` |
| `WarningCount` | number | `1` | `>= 0` |
| `CriticalCount` | number | `3` | `>= WarningCount` |

## Storage

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `Enabled` | Boolean | `$true` | Used by default selection |

## Uptime

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `WarningDays` | number | `45` | `>= 0` |
| `CriticalDays` | number | `90` | `>= WarningDays` |

## PendingReboot

| Key | Type | Default | Constraint |
|---|---|---|---|
| `PendingStatus` | string | `Warning` | `Warning` or `Critical` |
| `ExcludeReasons` | string array | Empty | PowerShell wildcard patterns matched against indicator names; excluded indicators stay in evidence but no longer set the pending state |

## PatchAge

| Key | Type | Default | Constraint |
|---|---|---:|---|
| `Enabled` | Boolean | `$true` | Used by default selection |
| `WarningDays` | number | `45` | `>= 0` |
| `CriticalDays` | number | `90` | `>= WarningDays` |

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
| `StorePaths` | string array | Machine `My` | Each path must begin `Cert:\`; add `Cert:\LocalMachine\WebHosting` for IIS web-hosting roles |
| `WarningDays` | number | `30` | `>= 0` |
| `CriticalDays` | number | `14` | `0`–warning |
| `SubjectExcludePatterns` | string array | Empty | PowerShell wildcard patterns; no empty entries |
| `IssuerExcludePatterns` | string array | Empty | PowerShell wildcard patterns matched against the issuer; no empty entries |
| `ThumbprintExclude` | string array | Empty | Exact match |
| `RequirePrivateKey` | Boolean | `$false` | Filters inventory |
| `MinTotalLifetimeDays` | number | `0` | `>= 0`; excludes certificates whose total lifetime (`NotAfter` minus `NotBefore`) is shorter; `0` keeps every certificate |
| `TreatShortLivedAsRotating` | Boolean | `$true` | Certificates whose total lifetime is at or below `WarningDays` are reported as auto-rotating: `Healthy` while valid, `Critical` once expired |

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

## Tls

| Key | Type | Default | Constraint / behavior |
|---|---|---:|---|
| `Enabled` | Boolean | `$true` | Used by default selection |
| `TimeoutMilliseconds` | number | `5000` | `100`–`60000` |
| `WarningDays` | number | `30` | `>= 0` |
| `CriticalDays` | number | `14` | `0`–warning |
| `RequireTrustedChain` | Boolean | `$true` | Untrusted chains become critical |
| `RequireNameMatch` | Boolean | `$true` | SNI/certificate identity mismatch becomes critical |
| `Endpoints` | array | Empty | Empty means skipped |

Each endpoint requires `Host`. Optional keys are `Name`, `Port` (default `443`), `Sni` (default `Host`), and per-endpoint `TimeoutMilliseconds`.

```powershell
Tls = @{
    Enabled             = $true
    TimeoutMilliseconds = 5000
    WarningDays         = 30
    CriticalDays        = 14
    RequireTrustedChain = $true
    RequireNameMatch    = $true
    Endpoints = @(
        @{
            Name = 'Application portal'
            Host = 'portal.contoso.invalid'
            Port = 443
            Sni  = 'portal.contoso.invalid'
        }
    )
}
```

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

## Change policy files

Report policy is deliberately separate from collection configuration. Collection configuration defines what is measured; a policy defines which results block a release, migration, or change.

```powershell
@{
    SchemaVersion = '1.0'
    FailOn = @('Critical', 'Unknown')
    MaximumWarnings = 0
    Ignore = @(
        @{
            ComputerName = 'lab-*'
            CheckName    = 'Uptime'
            Target       = '*'
            Status       = 'Warning'
        }
    )
}
```

`FailOn` accepts any result status, `MaximumWarnings` is the warning budget after ignore rules are applied, and every populated field in an `Ignore` rule must match. Values support PowerShell wildcards; supported rule keys are `ComputerName`, `CheckName`, `Category`, `Target`, and `Status`. Apply a policy with `Test-InfraPulseReport -PolicyPath`.
