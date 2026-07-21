[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Analyze', 'Test', 'Package', 'Verify')]
    [string]$Task = 'Verify',

    [switch]$Bootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$bootstrapDependencies = $Bootstrap.IsPresent

$repositoryRoot = $PSScriptRoot
$sourceRoot = Join-Path -Path $repositoryRoot -ChildPath 'src/InfraPulse'
$manifestPath = Join-Path -Path $sourceRoot -ChildPath 'InfraPulse.psd1'
$outputRoot = Join-Path -Path $repositoryRoot -ChildPath 'out'
$testResultRoot = Join-Path -Path $repositoryRoot -ChildPath 'test-results'
$analyzerSettingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$requiredModules = [ordered]@{
    Pester           = '5.7.1'
    PSScriptAnalyzer = '1.25.0'
}

function Write-BuildMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Information "[build] $Message" -InformationAction Continue
}

function Resolve-BuildDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$Version
    )

    # A module that is already imported must be reused: once its assembly is
    # loaded into the process, importing a second copy fails with an assembly
    # name conflict.
    $imported = Get-Module -Name $Name |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($null -ne $imported) {
        if ($imported.Version.Major -eq $Version.Major -and $imported.Version -ge $Version) {
            return $imported.Version
        }
        throw "Module '$Name' $($imported.Version) is already imported in this session, but version '$Version' or a newer $($Version.Major).x release is required. Run the build in a fresh PowerShell session."
    }

    $available = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.Version.Major -eq $Version.Major -and $_.Version -ge $Version } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($null -ne $available) {
        return $available.Version
    }

    if (-not $bootstrapDependencies) {
        throw "Required development module '$Name' version '$Version' or a newer $($Version.Major).x release is not installed. Re-run with -Bootstrap."
    }

    Write-BuildMessage "Installing $Name $Version for the current user."

    if ($PSVersionTable.PSVersion.Major -le 5) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $nuGetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        if ($null -eq $nuGetProvider) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false | Out-Null
        }
    }

    Install-Module -Name $Name -RequiredVersion $Version -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -Confirm:$false
    return $Version
}

function Import-BuildPester {
    [CmdletBinding()]
    param()

    $pesterVersion = Resolve-BuildDependency -Name Pester -Version $requiredModules.Pester

    # Invoke-ScriptAnalyzer resolves commands referenced by analyzed scripts,
    # which loads the newest installed Pester assembly into the process without
    # importing the module. A mismatched assembly cannot be unloaded, so fail
    # with an actionable message instead of a later Add-Type conflict.
    $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Pester' } |
        Select-Object -First 1
    if ($null -ne $loadedAssembly) {
        $loadedVersion = $loadedAssembly.GetName().Version
        $expectedVersion = [version]$pesterVersion
        if ($loadedVersion.Major -ne $expectedVersion.Major -or
            $loadedVersion.Minor -ne $expectedVersion.Minor -or
            [math]::Max($loadedVersion.Build, 0) -ne [math]::Max($expectedVersion.Build, 0)) {
            throw "Pester assembly $loadedVersion is already loaded in this process, but the build requires Pester $pesterVersion. Run the build in a fresh PowerShell session."
        }
    }

    Import-Module -Name Pester -RequiredVersion $pesterVersion
}

function Invoke-Clean {
    [CmdletBinding()]
    param()

    Write-BuildMessage 'Removing generated output.'
    foreach ($path in @($outputRoot, $testResultRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Invoke-ParseValidation {
    [CmdletBinding()]
    param()

    $parseErrors = New-Object System.Collections.Generic.List[object]
    $powerShellFiles = @(
        Get-ChildItem -Path $repositoryRoot -Recurse -File |
            Where-Object {
                $_.FullName -notlike "$outputRoot*" -and
                $_.FullName -notlike "$testResultRoot*" -and
                $_.Extension -in @('.ps1', '.psm1', '.psd1')
            }
    )

    foreach ($file in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        foreach ($errorRecord in @($errors)) {
            $parseError = [pscustomobject][ordered]@{
                File    = $file.FullName.Substring($repositoryRoot.Length + 1)
                Line    = $errorRecord.Extent.StartLineNumber
                Column  = $errorRecord.Extent.StartColumnNumber
                Message = $errorRecord.Message
            }
            $parseErrors.Add($parseError)
        }
    }

    foreach ($formatFile in Get-ChildItem -Path $sourceRoot -Recurse -Filter '*.ps1xml' -File) {
        try {
            $null = [xml](Get-Content -LiteralPath $formatFile.FullName -Raw)
        }
        catch {
            $parseError = [pscustomobject][ordered]@{
                File    = $formatFile.FullName.Substring($repositoryRoot.Length + 1)
                Line    = 0
                Column  = 0
                Message = $_.Exception.Message
            }
            $parseErrors.Add($parseError)
        }
    }

    if ($parseErrors.Count -gt 0) {
        $details = $parseErrors | Format-Table File, Line, Column, Message -AutoSize | Out-String
        throw "Parser validation failed:`n$details"
    }
}

function Invoke-ManifestValidation {
    [CmdletBinding()]
    param()

    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    $expectedCommands = @(
        'Compare-InfraPulseReport'
        'Export-InfraPulseComparison'
        'Export-InfraPulseReport'
        'Get-InfraPulseCheck'
        'Import-InfraPulseReport'
        'Invoke-InfraPulse'
        'New-InfraPulseConfiguration'
        'Test-InfraPulseComparison'
        'Test-InfraPulseConfiguration'
        'Test-InfraPulseReport'
    )
    $manifestCommands = @($manifest.ExportedFunctions.Keys | Sort-Object)
    $difference = Compare-Object -ReferenceObject ($expectedCommands | Sort-Object) -DifferenceObject $manifestCommands
    if ($null -ne $difference) {
        throw "Manifest exports do not match the expected public surface:`n$($difference | Format-Table | Out-String)"
    }

    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $manifestPath -Force -ErrorAction Stop
    $loadedCommands = @(Get-Command -Module InfraPulse -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
    $difference = Compare-Object -ReferenceObject ($expectedCommands | Sort-Object) -DifferenceObject $loadedCommands
    if ($null -ne $difference) {
        throw "Loaded command surface does not match the manifest:`n$($difference | Format-Table | Out-String)"
    }
    Remove-Module -Name InfraPulse -Force
}

function Invoke-Analyze {
    [CmdletBinding()]
    param()

    Write-BuildMessage 'Parsing PowerShell and format files.'
    Invoke-ParseValidation
    Invoke-ManifestValidation

    $analyzerVersion = Resolve-BuildDependency -Name PSScriptAnalyzer -Version $requiredModules.PSScriptAnalyzer
    Import-Module -Name PSScriptAnalyzer -RequiredVersion $analyzerVersion

    Write-BuildMessage 'Running PSScriptAnalyzer.'
    $analysisPaths = @(
        (Join-Path -Path $repositoryRoot -ChildPath 'src')
        (Join-Path -Path $repositoryRoot -ChildPath 'examples')
        (Join-Path -Path $repositoryRoot -ChildPath 'tools')
        (Join-Path -Path $repositoryRoot -ChildPath 'build.ps1')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $findings = @(
        foreach ($path in $analysisPaths) {
            $parameters = @{
                Path     = $path
                Settings = $analyzerSettingsPath
            }
            if ((Get-Item -LiteralPath $path).PSIsContainer) {
                $parameters.Recurse = $true
            }
            Invoke-ScriptAnalyzer @parameters
        }
    )

    if ($findings.Count -gt 0) {
        $details = $findings |
            Sort-Object ScriptPath, Line, RuleName |
            Select-Object Severity, RuleName, ScriptName, Line, Message |
            Format-Table -Wrap -AutoSize |
            Out-String
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s):`n$details"
    }
}

function Invoke-TestSuite {
    [CmdletBinding()]
    param()

    Import-BuildPester

    if (-not (Test-Path -LiteralPath $testResultRoot)) {
        $null = New-Item -Path $testResultRoot -ItemType Directory -Force
    }

    Write-BuildMessage 'Running Pester tests.'
    $configuration = [PesterConfiguration]::Default
    $configuration.Run.Path = Join-Path -Path $repositoryRoot -ChildPath 'tests'
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = Join-Path -Path $testResultRoot -ChildPath 'pester-results.xml'
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @($sourceRoot)
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    $configuration.CodeCoverage.OutputPath = Join-Path -Path $testResultRoot -ChildPath 'coverage.xml'

    $testRun = Invoke-Pester -Configuration $configuration
    if ($testRun.FailedCount -gt 0 -or $testRun.Result -ne 'Passed') {
        throw "Pester failed: $($testRun.FailedCount) failed, $($testRun.PassedCount) passed, $($testRun.SkippedCount) skipped."
    }
}

function Invoke-Package {
    [CmdletBinding()]
    param()

    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $version = [string]$manifest.ModuleVersion
    $packageRoot = Join-Path -Path $outputRoot -ChildPath 'package'
    $stagingModule = Join-Path -Path $packageRoot -ChildPath 'InfraPulse'
    $archivePath = Join-Path -Path $outputRoot -ChildPath "InfraPulse-$version.zip"
    $hashPath = "$archivePath.sha256"

    Write-BuildMessage "Packaging InfraPulse $version."
    if (Test-Path -LiteralPath $packageRoot) {
        Remove-Item -LiteralPath $packageRoot -Recurse -Force
    }
    $null = New-Item -Path $stagingModule -ItemType Directory -Force
    Copy-Item -Path (Join-Path -Path $sourceRoot -ChildPath '*') -Destination $stagingModule -Recurse -Force

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path $stagingModule -DestinationPath $archivePath -CompressionLevel Optimal

    $verificationRoot = Join-Path -Path $outputRoot -ChildPath 'verification'
    if (Test-Path -LiteralPath $verificationRoot) {
        Remove-Item -LiteralPath $verificationRoot -Recurse -Force
    }
    Expand-Archive -Path $archivePath -DestinationPath $verificationRoot -Force
    $packagedManifest = Join-Path -Path $verificationRoot -ChildPath 'InfraPulse/InfraPulse.psd1'
    $null = Test-ModuleManifest -Path $packagedManifest -ErrorAction Stop

    $hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
    "$($hash.Hash.ToLowerInvariant()) *$([System.IO.Path]::GetFileName($archivePath))" |
        Set-Content -LiteralPath $hashPath -Encoding Ascii

    Remove-Item -LiteralPath $packageRoot -Recurse -Force
    Remove-Item -LiteralPath $verificationRoot -Recurse -Force

    Write-BuildMessage "Created $archivePath"
    Write-BuildMessage "Created $hashPath"
}

switch ($Task) {
    'Clean' {
        Invoke-Clean
    }
    'Analyze' {
        Invoke-Analyze
    }
    'Test' {
        Invoke-TestSuite
    }
    'Package' {
        Invoke-Package
    }
    'Verify' {
        Invoke-Clean
        # Import Pester before the analysis stage: analyzing build.ps1 makes
        # PSScriptAnalyzer auto-load the newest installed Pester, which would
        # conflict with the version the test suite imports afterwards.
        Import-BuildPester
        Invoke-Analyze
        Invoke-TestSuite
        Invoke-Package
    }
}
