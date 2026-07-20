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

`Include` and `Exclude` use PowerShell wildcard matching against drive identifiers such as `C:`.

## Memory

**Category:** Capacity
**Platform:** Windows
**Source:** `Win32_OperatingSystem`

Evaluates current available physical memory as a percentage of visible physical memory. This is a point-in-time signal, not a trend. Use it for triage or validation and correlate warnings with sustained telemetry before resizing a workload.

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

## Services

**Category:** Availability
**Platform:** Windows
**Sources:** `Get-Service` and `Win32_Service`

Each configured service has:

- `Name`: service name, not display name
- `ExpectedStatus`: `Running`, `Stopped`, or `Paused`
- `Severity`: result when missing or in the wrong state

Start mode is collected as evidence when available but is not currently evaluated. Configure services by server role; a universal service list creates noise and hides the operational intent of the scan.

## Certificates

**Category:** Security
**Platform:** Windows
**Source:** PowerShell certificate provider

Scans configured `Cert:\LocalMachine\...` stores and emits individual warning/critical results for expired or expiring certificates plus one inventory summary.

Filters:

- `SubjectExcludePatterns`: PowerShell wildcard patterns matched against the subject
- `IssuerExcludePatterns`: PowerShell wildcard patterns matched against the issuer
- `ThumbprintExclude`: exact thumbprints
- `RequirePrivateKey`: include only certificates with an accessible private key
- `MinTotalLifetimeDays`: exclude certificates whose total lifetime (`NotAfter` minus `NotBefore`) is shorter than the given number of days; `0` (the default) keeps every certificate

Auto-rotated short-lived certificates — for example the Entra ID device certificate issued by `CN=MS-Organization-P2P-Access [2026]` (about one day of lifetime) or the Azure Virtual Desktop agent certificate `CN=RDSAGENT.WVD` (about 26 days) — can never satisfy a 30-day warning threshold and would otherwise alert on every scan. `ThumbprintExclude` does not help because the thumbprint changes on each rotation. Exclude them by issuer, e.g. `IssuerExcludePatterns = @('CN=MS-Organization-P2P-Access*')`, or set `MinTotalLifetimeDays` above their rotation lifetime so every automatically renewed certificate stays out of the expiry evaluation.

An expiring certificate must still be mapped to its bindings and workload before renewal. InfraPulse reports the evidence but does not infer service ownership or alter certificate stores.

## EventLog

**Category:** Reliability
**Platform:** Windows
**Source:** `Get-WinEvent`

For each configured log, InfraPulse counts matching events inside `LookbackHours`, applies level/provider/event-ID filters, and records the five highest-volume providers plus up to five samples.

Default levels are `1` (Critical) and `2` (Error). `MaxEvents` caps collection cost. When the query reaches that cap, InfraPulse preserves the finding as `Unknown` unless the returned matching events already meet a warning or critical threshold. This prevents an incomplete query from being reported as healthy. Keep `MaxEvents` comfortably above `CriticalCount` and reduce `LookbackHours` for high-volume logs.

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
