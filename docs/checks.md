# Check reference

All checks are read-only. Threshold comparisons are inclusive: reaching a configured boundary changes the result state.

## Disk

**Category:** Capacity
**Platform:** Windows
**Source:** `Win32_LogicalDisk` with `DriveType = 3`

Each matching fixed volume produces one result. A volume is:

- `Critical` when free percentage is less than or equal to `CriticalFreePercent` **or** free GiB is less than or equal to `CriticalFreeGB`.
- `Warning` when either warning boundary is reached and no critical boundary is reached.
- `Healthy` otherwise.

Both relative and absolute thresholds matter. A large data volume can have a low percentage but adequate working space; a small system volume can have a reasonable percentage but too little absolute space.

Thresholds are evaluated against unrounded values derived from the raw byte counts; the rounded `FreeGB` and `FreePercent` evidence fields are display values only, so a volume sitting exactly on a rounded boundary cannot flip state through rounding.

`Volumes` overrides thresholds per volume: each entry names a `DeviceId` (wildcards supported), and every threshold key it provides replaces the global value for matching volumes while omitted keys fall back. This addresses large data volumes where the percentage threshold alone is misleading — 80 GB free on a 420 GB volume is not a capacity problem even though it is below 20%.

`Include` and `Exclude` use PowerShell wildcard matching against drive identifiers such as `C:`.

## Memory

**Category:** Capacity
**Platform:** Windows
**Source:** `Win32_OperatingSystem`

Evaluates current available physical memory as a percentage of visible physical memory, and the commit charge as a percentage of the commit limit — a host can suffocate at its commit limit while physical memory still looks fine. The result status is the worse of the two evaluations, and page-file allocation and usage are recorded as evidence. This is a point-in-time signal, not a trend. Use it for triage or validation and correlate warnings with sustained telemetry before resizing a workload.

## Cpu

**Category:** Capacity
**Platform:** Windows
**Source:** `Win32_Processor.LoadPercentage`

Averages processor load over a short sample series (default three samples, one second apart) to separate sustained pressure from momentary spikes. Evidence carries the individual samples, the logical processor count, and the five largest processes by working set. The sampling adds roughly `SampleCount × SampleIntervalSeconds` to the scan duration.

## ScheduledTasks

**Category:** Availability
**Platform:** Windows
**Source:** `Get-ScheduledTask` / `Get-ScheduledTaskInfo`

Finds enabled scheduled tasks whose last run ended with a failure result — the classic silent failure mode of backup and maintenance jobs. The Microsoft namespace (`\Microsoft\*`) is excluded by default so the check targets operator-created jobs; `IncludePaths`, `ExcludePaths`, and `ExcludeTasks` use PowerShell wildcards. Benign result codes are pre-excluded (`267009` currently running, `267011` never run) and configurable through `ExcludeResults`. Reported as `Unknown` where the ScheduledTasks module is unavailable.

## Defender

**Category:** Security
**Platform:** Windows
**Source:** `Get-MpComputerStatus`

Validates that the Microsoft Defender engine and real-time protection are enabled and that antivirus signatures are current. Disabled protection is `Critical`; signature age is evaluated against `SignatureWarningDays`/`SignatureCriticalDays`. When the Defender cmdlets are unavailable or fail — typically because a third-party antivirus owns the host — the check reports `Skipped` with a note rather than alarming.

## Stability

**Category:** Reliability
**Platform:** Windows
**Source:** targeted System event log queries

Counts crash indicators inside `LookbackDays` (default 7): bugchecks (event 1001), kernel power-loss events (41), unexpected shutdowns (6008), and WHEA hardware errors. Each indicator is queried separately so one unreadable provider does not hide the others; evidence lists the individual incidents and the number of minidump files. When every query fails, the check reports `Unknown`.

## Storage

**Category:** Reliability
**Platform:** Windows
**Source:** `Get-PhysicalDisk` / `Get-Volume`

Reports the health status of physical disks and fixed volumes — the condition of the storage rather than its free space, complementing the Disk check. Any non-healthy physical disk is `Critical` (`Warning` state maps to `Warning`), unhealthy volumes are reported per volume, and a summary result carries the full inventory. On targets without the Storage cmdlets the check reports `Unknown`.

## Uptime

**Category:** Lifecycle
**Platform:** Windows
**Source:** `Win32_OperatingSystem.LastBootUpTime`

Flags hosts whose uptime reaches the warning or critical day threshold. Long uptime is not automatically a fault; it is an operational signal for patch cadence, deferred maintenance, and reboot-dependent changes.

## PendingReboot

**Category:** Lifecycle
**Platform:** Windows
**Sources:**

- Component Based Servicing `RebootPending`
- Windows Update `RebootRequired`
- Session Manager pending file-renames
- `UpdateExeVolatile`
- Active/configured computer-name mismatch
- Configuration Manager `CCM_ClientUtilities`, when present

Any detected indicator produces the configured `PendingStatus` (`Warning` or `Critical`) and records every reason in evidence. Missing optional registry values and absent Configuration Manager namespaces are not errors.

`ExcludeReasons` accepts PowerShell wildcard patterns matched against the indicator names (`Component Based Servicing`, `Windows Update`, `Pending file rename operations`, `UpdateExeVolatile`, `Computer rename`, `Configuration Manager client`). Excluded indicators no longer set the pending state — a host whose only indicators are excluded reports `Healthy` — but they remain visible in the result evidence under `ExcludedReasons`. This is intended for environments where an indicator is structurally noisy, for example multi-session hosts whose agents re-create pending file renames within hours of every scheduled reboot; prefer excluding the specific indicator over tolerating a permanent warning.

## PatchAge

**Category:** Lifecycle
**Platform:** Windows
**Source:** `Win32_QuickFixEngineering`

Evaluates the number of days since the most recent installed Windows update and flags hosts that fall behind the expected patch cadence. Evidence includes the latest KB identifier, the installation date, and the five most recent updates.

`Win32_QuickFixEngineering` lists servicing-stack and CBS-installed updates; updates delivered through other channels (for example full feature upgrades or third-party installers) may not appear. When no entry carries an installation date, the check reports `Unknown` instead of guessing.

The check also records the last boot time: when the newest update was installed after the last boot, the evidence carries `AwaitingReboot = true` and the message notes that a restart is required to activate it. The status itself stays driven by the update age.

## Services

**Category:** Availability
**Platform:** Windows
**Sources:** `Get-Service` and `Win32_Service`

Each configured service has:

- `Name`: service name, not display name
- `ExpectedStatus`: `Running`, `Stopped`, or `Paused`
- `Severity`: result when missing or in the wrong state

Start mode is collected as evidence when available but is not currently evaluated. Configure services by server role; a universal service list creates noise and hides the operational intent of the scan.

A missing service produces the configured `Severity`. A failed service query — for example access denied or a Service Control Manager communication failure — remains `Unknown` with the captured error, because it does not prove the service is absent.

## Certificates

**Category:** Security
**Platform:** Windows
**Source:** PowerShell certificate provider

Scans configured `Cert:\LocalMachine\...` stores and emits individual warning/critical results for expired or expiring certificates plus one inventory summary. Each configured store that does not exist on the target produces an explicit `Unknown` result so a scan cannot silently measure fewer stores than the configuration promises; remove unused stores from `StorePaths` for roles that do not provision them.

Filters:

- `SubjectExcludePatterns`: PowerShell wildcard patterns matched against the subject
- `IssuerExcludePatterns`: PowerShell wildcard patterns matched against the issuer
- `ThumbprintExclude`: exact thumbprints
- `RequirePrivateKey`: include only certificates with an accessible private key
- `MinTotalLifetimeDays`: exclude certificates whose total lifetime (`NotAfter` minus `NotBefore`) is shorter than the given number of days; `0` (the default) keeps every certificate

A certificate whose total lifetime (`NotAfter` minus `NotBefore`) is at or below `WarningDays` can never satisfy the expiry policy by construction — for example the Entra ID device certificate issued by `CN=MS-Organization-P2P-Access [2026]` (about one day of lifetime) or the Azure Virtual Desktop agent certificate `CN=RDSAGENT.WVD` (about 26 days) against the default 30-day warning threshold. With `TreatShortLivedAsRotating` (default `$true`), such certificates are classified as auto-rotating: they stay visible as `Healthy` results with `Rotating` and `TotalLifetimeDays` evidence while valid, and turn `Critical` only when they expire, because an expired short-lived certificate means the automatic rotation stopped working. Set `TreatShortLivedAsRotating = $false` to evaluate them against the thresholds like any other certificate.

Certificates can also be removed from the evaluation entirely: `ThumbprintExclude` does not help for rotating certificates because the thumbprint changes on each rotation, but they can be excluded by issuer, e.g. `IssuerExcludePatterns = @('CN=MS-Organization-P2P-Access*')`, or with `MinTotalLifetimeDays` above their rotation lifetime. Exclusions take precedence: an excluded certificate never appears in the report.

An expiring certificate must still be mapped to its bindings and workload before renewal. InfraPulse reports the evidence but does not infer service ownership or alter certificate stores.

## EventLog

**Category:** Reliability
**Platform:** Windows
**Source:** `Get-WinEvent`

For each configured log, InfraPulse counts matching events inside `LookbackHours`, applies level/provider/event-ID filters, and records the five highest-volume providers plus up to five samples.

Default levels are `1` (Critical) and `2` (Error). `MaxEvents` caps collection cost. The query reads one record beyond the cap, so a result set that exactly fills the cap is still reported precisely; only a genuinely truncated query is treated as incomplete. A truncated query is preserved as `Unknown` unless the returned matching events already meet a warning or critical threshold; in that case the result reports the count as a lower bound (`At least N …`, observed value `N+`) because the true volume is unknown. This prevents an incomplete query from being reported as healthy or a capped count from being read as exact. Keep `MaxEvents` comfortably above `CriticalCount` and reduce `LookbackHours` for high-volume logs.

`IncludeMessages` is off by default because message rendering can be expensive and may expose operational or user data.

## Dns

**Category:** Connectivity
**Platform:** Cross-platform

Runs from the evaluated target, not from the controller. Targets can be strings using global `QueryType` and `Server`, or dictionaries with per-target overrides:

```powershell
Targets = @(
    'login.microsoftonline.com'
    @{ Name = '_ldap._tcp.dc._msdcs.contoso.invalid'; Type = 'SRV'; Server = '10.20.0.10' }
)
```

Supported record types: `A`, `AAAA`, `CNAME`, `MX`, `NS`, `PTR`, `SRV`, and `TXT`.

When `Resolve-DnsName` is unavailable, the fallback supports only `A` and `AAAA` through .NET and filters the result by address family. The fallback cannot target a custom DNS server; configuring `Server` therefore requires `Resolve-DnsName` on the evaluated host. Unsupported record-type or custom-resolver requests are reported as `Unknown`, while an attempted lookup that fails is `Critical`.

## Tcp

**Category:** Connectivity
**Platform:** Cross-platform

Attempts a TCP connection from the evaluated target with a deterministic timeout. A successful handshake is `Healthy`; timeout, refusal, name-resolution failure, and route failure are `Critical`.

```powershell
Endpoints = @(
    @{ Name = 'HTTPS'; Host = 'app.contoso.invalid'; Port = 443 }
    @{ Name = 'LDAP'; Host = 'dc01.contoso.invalid'; Port = 389; TimeoutMilliseconds = 5000 }
)
```

This validates network reachability and listener acceptance only. It does not validate TLS identity, application protocol, authentication, or end-to-end transaction health.

## Tls

**Category:** Security
**Platform:** Cross-platform
**Protocols:** TCP and TLS

The TLS check opens a TCP connection from the evaluated target, performs a TLS client handshake using the configured SNI name, captures the remote certificate, and evaluates:

- handshake success and timeout,
- certificate identity against SNI,
- local chain trust without online revocation checks,
- certificate validity and days remaining,
- negotiated TLS protocol.

```powershell
Endpoints = @(
    @{
        Name = 'Application portal'
        Host = 'portal.contoso.invalid'
        Port = 443
        Sni  = 'portal.contoso.invalid'
    }
)
```

A failed handshake, required name mismatch, required untrusted chain, expired certificate, or certificate inside the critical window is `Critical`. A certificate inside the warning window is `Warning`. Evidence contains certificate identity, thumbprint, validity dates, chain status, policy errors, protocol, and handshake duration.

On PowerShell 7 targets the handshake follows the operating-system protocol defaults, including TLS 1.3 where available. On Windows PowerShell 5.1 targets the check explicitly offers TLS 1.0–1.2, because the .NET Framework default would otherwise fall back to SSL3/TLS 1.0 and fail against modern endpoints; TLS 1.3-only endpoints therefore require a PowerShell 7 target.

The check does not perform an HTTP request, validate application authentication, inspect response content, or test end-to-end business transactions.

## TimeSync

**Category:** Connectivity
**Platform:** Cross-platform
**Protocol:** SNTP over UDP/123

InfraPulse sends an NTP client request over IPv4 or IPv6, verifies the echoed originate timestamp, validates protocol version, server mode, synchronization state, and stratum, then calculates offset with the standard four-timestamp formula:

```text
offset = ((t2 - t1) + (t3 - t4)) / 2
```

The absolute offset determines status. Evidence includes server address, signed offset, absolute offset, round-trip time, stratum, NTP version, and mode.

The check is disabled by default because UDP/123 is frequently filtered and organizations normally enforce an internal time hierarchy. Configure authoritative sources for the evaluated network rather than relying on the example public server.
