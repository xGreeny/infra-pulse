# Security policy

## Supported versions

Security fixes are applied to the latest released major version.

| Version | Supported |
|---|:---:|
| 1.x | Yes |
| < 1.0 | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability-reporting feature for this repository. Include:

- Affected version and PowerShell edition
- Target operating system and remoting mode
- Minimal reproduction steps
- Expected and observed behavior
- Security impact
- Any proposed mitigation

Reports are acknowledged as soon as practical. Confirmed issues are tracked privately until a fix and coordinated disclosure are ready.

## Security model

InfraPulse is a read-only assessment tool, but it executes collection commands with the permissions of the current process or supplied PSSession. Treat it with the same care as other administrative PowerShell modules:

- Import releases only from this repository or a trusted internal mirror.
- Verify the release archive against the published SHA-256 file.
- Review configuration and code before deployment into privileged automation.
- Use the least-privileged identity that can read the selected data sources.
- Prefer HTTPS listeners, Kerberos, or caller-managed hardened sessions for remote use.
- Do not embed credentials in `.psd1`, scripts, workflow files, or shell history.
- Protect generated reports according to the infrastructure metadata they contain.

InfraPulse does not execute remediation, persist credentials, create scheduled tasks, alter firewall rules, restart services, or write to target systems.

## Generated HTML reports

HTML exports encode report values before insertion, contain no external assets, declare `noindex`, and apply a restrictive content-security policy. Reports can still contain sensitive operational metadata. Store and transmit them according to the same controls used for server inventories and diagnostic logs.
