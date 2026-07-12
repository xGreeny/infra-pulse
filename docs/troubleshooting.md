# Troubleshooting

## Start with the effective configuration

```powershell
$validation = Test-InfraPulseConfiguration -Path .\config\my-environment.psd1
$validation | Format-List Source, IsValid, Errors, Warnings
$validation.EffectiveConfiguration | ConvertTo-Json -Depth 10
```

InfraPulse does not contact a target when configuration validation fails.

## Capture verbose execution

```powershell
$VerbosePreference = 'Continue'
$report = Invoke-InfraPulse -ComputerName 'srv-app-01' -Check Disk, Services -Verbose
$report.Results | Format-List *
```

Use `-FailFast` when the original terminating exception and stack location are more useful than a partial report:

```powershell
Invoke-InfraPulse -ComputerName 'srv-app-01' -Check Certificates -FailFast -Verbose
```

## Connection result is Critical

A `Connection` control result means InfraPulse could not open the temporary PSSession. Reproduce with native remoting commands and review [`remoting.md`](remoting.md).

## Execution or check result is Unknown

`Unknown` means health could not be established. Inspect:

```powershell
$result = $report.Results | Where-Object Status -EQ Unknown
$result | Select-Object ComputerName, CheckName, Target, Message, Error
$result.Evidence | ConvertTo-Json -Depth 8
```

Typical causes are missing permissions, unavailable providers/cmdlets, constrained endpoints, malformed target data, or platform mismatch.

## Disk returns no matching volumes

Review wildcard selection:

```powershell
$validation.EffectiveConfiguration.Checks.Disk | Format-List
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' |
    Select-Object DeviceID, VolumeName, Size, FreeSpace
```

Exclusions take precedence over inclusions.

## Certificates reports missing stores

Certificate-provider paths differ by server role. Confirm them on the target:

```powershell
Invoke-Command -ComputerName 'srv-app-01' -ScriptBlock {
    Get-ChildItem Cert:\LocalMachine
}
```

Remove stores that do not exist on that role or maintain separate role configurations.

## EventLog is noisy or truncated

- Reduce `LookbackHours` for burst-oriented triage.
- Exclude known-benign providers or event IDs only after operational review.
- Increase `MaxEvents` above `CriticalCount`.
- Keep `IncludeMessages = $false` for broad scans; enable it only for targeted diagnosis.

A capped query is incomplete. InfraPulse reports it as `Unknown` unless the returned matching events already meet a warning or critical threshold.

## DNS succeeds on the controller but fails in InfraPulse

The query runs on the evaluated target. Compare target-side behavior:

```powershell
Invoke-Command -ComputerName 'srv-app-01' -ScriptBlock {
    Resolve-DnsName login.microsoftonline.com -DnsOnly
    Get-DnsClientServerAddress
}
```

Check suffix policy, resolver selection, split-brain zones, conditional forwarders, and target firewall rules.

A configured custom DNS server requires `Resolve-DnsName` on the target. Hosts using the .NET fallback can query only `A` and `AAAA` records through their configured resolver path.

## TCP succeeds from an admin workstation but fails in InfraPulse

The socket opens from the target. Validate the same source/destination path:

```powershell
Invoke-Command -ComputerName 'srv-app-01' -ScriptBlock {
    Test-NetConnection login.microsoftonline.com -Port 443
}
```

A successful TCP result does not prove TLS or application health.

## TimeSync reports Unknown

Confirm all of the following:

- DNS resolves the NTP server from the target.
- UDP/123 is permitted in both directions.
- The server returns NTP server mode 4 and a non-zero stratum.
- The server is synchronized and does not send a kiss-of-death response.
- The configured timeout is appropriate for the path.

On Windows, compare with:

```powershell
w32tm /query /status
w32tm /query /peers
w32tm /stripchart /computer:time.windows.com /samples:5 /dataonly
```

## HTML report opens without styling or filtering

The report is a single file with inline assets. Confirm it was not rewritten by a mail gateway, document-management system, or security product. Filtering requires JavaScript; the health content and tables remain readable when scripts are disabled.
