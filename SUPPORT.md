# Support

## Before opening an issue

1. Run the command again with `-Verbose`.
2. Validate the effective configuration:

   ```powershell
   Test-InfraPulseConfiguration -Path .\config\my-environment.psd1
   ```

3. Confirm the selected check's prerequisites in [`docs/checks.md`](docs/checks.md).
4. For remote failures, test the underlying session independently with `New-PSSession` and `Invoke-Command`.
5. Reproduce the issue with the latest release.

## Useful diagnostic data

Include the following in a support issue after removing environment-sensitive values:

```powershell
$PSVersionTable
Get-Module InfraPulse | Select-Object Name, Version, Path
Get-InfraPulseCheck
Test-InfraPulseConfiguration -Path .\config\my-environment.psd1
```

Also include the failing command, full error record, operating-system family, whether the target is local or remote, and the smallest sanitized configuration that reproduces the behavior.

Do not attach production event logs, customer reports, credentials, tenant identifiers, private IP plans, or unredacted certificate data.
