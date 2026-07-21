# Publishing the repository

## PowerShell Gallery

The module folder under `src/InfraPulse` is Gallery-ready (manifest tags, license, and project URI are set). Publish a released version manually with an API key from `https://www.powershellgallery.com/account/apikeys`:

```powershell
Copy-Item "C:\Users\FlurinGubler\OneDrive - Beltronic - Neseco IT GmbH\Git\infra-pulse\infra-pulse\src\InfraPulse" "$env:TEMP\InfraPulse" -Recurse -Force
Publish-PSResource -Path "$env:TEMP\InfraPulse" -Repository PSGallery -ApiKey '<DEIN-API-KEY>'
Remove-Item "$env:TEMP\InfraPulse" -Recurse -Force
```

Publish only tagged, released states so the Gallery version always matches a GitHub release. Hosts then install and update with `Install-PSResource InfraPulse` (or `Install-Module InfraPulse`).

This repository is prepared for `https://github.com/xGreeny/infra-pulse`.

## Initial publication

Create an empty public repository named `infra-pulse` under the `xGreeny` account, then run from the extracted repository directory:

```powershell
git init
git branch -M main
git add .
git commit -m "Release InfraPulse 1.0.0"
git remote add origin https://github.com/xGreeny/infra-pulse.git
git push -u origin main
```

The first push runs CI on Windows PowerShell 5.1 and PowerShell 7. Do not create the release tag until the workflow is green.

## Repository settings

Recommended description:

```text
Read-only PowerShell health checks and self-contained reports for Windows infrastructure.
```

Recommended topics:

```text
powershell windows-server infrastructure health-check system-administration winrm automation pester devops
```

Recommended settings:

- Enable Issues and Discussions only when you intend to maintain them.
- Enable private vulnerability reporting.
- Enable Dependabot security updates.
- Enable secret scanning and push protection where available.
- Protect `main` after the initial push.
- Require the `verify` workflow before merging.
- Require branches to be up to date before merging.
- Block force pushes and branch deletion.
- Use squash merging for a concise history.

## First release

The release workflow expects a tag that exactly matches the module manifest version:

```powershell
.\build.ps1 -Task Verify -Bootstrap
git status --short
git tag -a v1.0.0 -m "InfraPulse 1.0.0"
git push origin v1.0.0
```

The workflow verifies the repository, builds `InfraPulse-1.0.0.zip`, creates a SHA-256 file, and publishes both files to the GitHub release.

## Social preview

Upload [`assets/social-preview.png`](../assets/social-preview.png) under **Settings → General → Social preview**. The file is already prepared at GitHub's recommended 1280 × 640 pixel format; `assets/social-preview.svg` is the editable source.

## Profile placement

Pin `infra-pulse` after the first release and a clean CI run. A strong pinned description is the repository description above; the report screenshot supplies the visual proof, while the test and release badges show engineering discipline.
