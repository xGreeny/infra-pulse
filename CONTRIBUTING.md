# Contributing

InfraPulse accepts focused changes that improve correctness, operational safety, compatibility, or clarity.

## Development baseline

- Windows PowerShell 5.1 or PowerShell 7+
- Git
- Pester 5.7.1
- PSScriptAnalyzer 1.25.0

The build script installs the pinned development dependencies for the current user:

```powershell
.\build.ps1 -Task Verify -Bootstrap
```

## Change workflow

1. Create a branch from `main`.
2. Keep each change scoped to one behavior or concern.
3. Add or update Pester tests for every behavior change.
4. Update operator documentation when configuration, output, or prerequisites change.
5. Run `./build.ps1 -Task Verify -Bootstrap` in a clean session.
6. Open a pull request using the repository template.

## Engineering rules

- Checks are read-only. Remediation belongs in a separate tool or explicit operator workflow.
- Public commands return objects; formatting and export remain separate concerns.
- Errors must be actionable and preserve the underlying exception message.
- New configuration keys require defaults, validation, documentation, and tests.
- New result fields require a schema-version decision and documentation update.
- Remote code must run under both Windows PowerShell 5.1 and PowerShell 7 unless the check is explicitly documented otherwise.
- Samples and tests must use fictional or reserved infrastructure data.
- No credentials, tenant identifiers, production logs, internal hostnames, or customer data may be committed.

## Commit style

Use imperative, specific commit subjects:

```text
Add certificate thumbprint exclusions
Fix remote session cleanup after scan failure
Document constrained endpoint requirements
```

## Pull-request acceptance

A pull request is ready to merge when:

- CI passes on both PowerShell engines.
- PSScriptAnalyzer reports no warning or error findings.
- Unit tests cover threshold boundaries and failure behavior.
- Generated files are not committed.
- Public help and documentation match the implementation.
- The change preserves read-only behavior.
