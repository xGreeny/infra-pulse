# Remoting

InfraPulse supports three execution modes:

1. Local execution with `localhost`, `.`, loopback addresses, or the local host name.
2. Temporary WSMan sessions created from `-ComputerName`.
3. Caller-owned `PSSession` objects supplied through the pipeline or `-Session`.

## Temporary WSMan sessions

```powershell
$credential = Get-Credential

Invoke-InfraPulse `
    -ComputerName 'srv-app-01.contoso.invalid' `
    -Credential $credential `
    -Authentication Kerberos `
    -UseSSL `
    -ConfigurationPath .\config\infra-pulse.example.psd1
```

InfraPulse creates one session per target, runs the scan, and removes the session in a `finally` block. The credential is passed to `New-PSSession` and is not persisted.

`ConnectionTimeoutSeconds` controls session open timeout. InfraPulse sets a larger operation timeout so individual checks have room to complete after the connection is established.

## Caller-owned sessions

Use existing sessions when transport or endpoint policy needs to remain outside InfraPulse:

```powershell
$sessionOption = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 60000
$sessions = New-PSSession `
    -ComputerName 'srv-app-01', 'srv-file-01' `
    -UseSSL `
    -Authentication Kerberos `
    -SessionOption $sessionOption

try {
    $sessions | Invoke-InfraPulse -Check Disk, Memory, Services
}
finally {
    $sessions | Remove-PSSession
}
```

InfraPulse never removes caller-owned sessions. PowerShell 7 callers can also supply sessions they created through SSH remoting; InfraPulse treats them as opaque execution contexts.

## Target prerequisites

For Windows checks, the remoting identity needs read access to the selected data sources:

- CIM/WMI classes for inventory, disk, memory, uptime, service start mode
- Service Control Manager for service state
- Registry paths used by pending-reboot detection
- LocalMachine certificate stores
- Selected Windows event logs

Full local administrator rights are not an architectural requirement, but default Windows permissions and remoting endpoints frequently make them the easiest initial test. For production automation, prefer a constrained endpoint or delegated identity that exposes only the required read operations.

Connectivity checks execute from the target. The target therefore needs DNS access, outbound TCP access to configured endpoints, or outbound UDP/123 to configured NTP servers.

## Authentication guidance

- Prefer Kerberos inside an Active Directory trust boundary.
- Prefer HTTPS listeners when policy requires transport encryption beyond the authentication protocol.
- Avoid Basic authentication unless it is explicitly approved and protected by HTTPS.
- Do not enable `TrustedHosts` broadly to bypass name or trust problems.
- Do not store `PSCredential` exports or plaintext secrets in the repository.
- Use a separate automation identity with auditable assignment and only the permissions needed by enabled checks.

## Connection failures

A failed temporary connection produces a report with one `Critical` `Connection` result unless `-FailFast` or `ContinueOnError = $false` is active.

Troubleshoot the transport before InfraPulse:

```powershell
Test-WSMan -ComputerName 'srv-app-01'
$session = New-PSSession -ComputerName 'srv-app-01' -Credential (Get-Credential)
Invoke-Command -Session $session -ScriptBlock { $PSVersionTable; hostname }
```

Common causes:

- Name resolution points to the wrong address.
- WinRM is not configured or the listener does not match `-UseSSL`/`-Port`.
- Firewall policy blocks the listener.
- Kerberos SPN, delegation, time, or trust is invalid.
- The account is not authorized for the endpoint.
- A proxy or network security device interrupts the session.
- The endpoint uses a language mode or session configuration that blocks required commands.

## Double-hop behavior

Most built-in checks query only the target itself. DNS, TCP, and SNTP open outbound connections from the target without forwarding the caller's Windows credentials. InfraPulse does not attempt CredSSP, delegation configuration, or credential forwarding to a second host.
