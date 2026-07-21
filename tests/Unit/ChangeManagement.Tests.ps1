BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/InfraPulse/InfraPulse.psd1'
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ModulePath -Force -ErrorAction Stop

    $script:Snapshots = InModuleScope InfraPulse {
        $computer = 'SRV-CMP-01'
        $beforeResults = @(
            New-InfraPulseResult -Status Healthy -CheckName Disk -Category Capacity -ComputerName $computer -Target 'C:' -Message 'Plenty of space.' -ObservedValue '50.00% / 100.00 GB'
            New-InfraPulseResult -Status Warning -CheckName Disk -Category Capacity -ComputerName $computer -Target 'D:' -Message 'Low space.' -ObservedValue '15.00% / 15.00 GB'
            New-InfraPulseResult -Status Critical -CheckName Services -Category Availability -ComputerName $computer -Target 'Spooler' -Message 'Stopped.' -ObservedValue 'Stopped'
            New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName $computer -Target 'Physical memory' -Message 'Fine.' -ObservedValue '40.00%'
            New-InfraPulseResult -Status Healthy -CheckName Uptime -Category Lifecycle -ComputerName $computer -Target 'Operating system' -Message 'Fine.' -ObservedValue '1.00 days'
            New-InfraPulseResult -Status Warning -CheckName Certificates -Category Security -ComputerName $computer -Target 'CN=app.contoso.invalid' -Message 'Expiring.' -ObservedValue '20.00 days'
        )
        $afterResults = @(
            New-InfraPulseResult -Status Critical -CheckName Disk -Category Capacity -ComputerName $computer -Target 'C:' -Message 'Almost full.' -ObservedValue '5.00% / 10.00 GB'
            New-InfraPulseResult -Status Healthy -CheckName Disk -Category Capacity -ComputerName $computer -Target 'D:' -Message 'Recovered.' -ObservedValue '35.00% / 35.00 GB'
            New-InfraPulseResult -Status Warning -CheckName Services -Category Availability -ComputerName $computer -Target 'Spooler' -Message 'Degraded.' -ObservedValue 'Paused'
            New-InfraPulseResult -Status Healthy -CheckName Memory -Category Capacity -ComputerName $computer -Target 'Physical memory' -Message 'Fine.' -ObservedValue '45.00%'
            New-InfraPulseResult -Status Healthy -CheckName Uptime -Category Lifecycle -ComputerName $computer -Target 'Operating system' -Message 'Fine.' -ObservedValue '1.00 days'
            New-InfraPulseResult -Status Warning -CheckName EventLog -Category Reliability -ComputerName $computer -Target 'Application' -Message 'Noisy.' -ObservedValue 30
            New-InfraPulseResult -Status Healthy -CheckName Tcp -Category Connectivity -ComputerName $computer -Target 'Portal' -Message 'Reachable.' -ObservedValue $true
        )

        @{
            Before = New-InfraPulseReport -RequestedComputerName $computer -ComputerName $computer -Inventory $null -Results $beforeResults -DurationMs 100 -RunId '11111111-1111-4111-8111-111111111111' -ConfigurationFingerprint 'fingerprint-a'
            After  = New-InfraPulseReport -RequestedComputerName $computer -ComputerName $computer -Inventory $null -Results $afterResults -DurationMs 100 -RunId '22222222-2222-4222-8222-222222222222' -ConfigurationFingerprint 'fingerprint-a'
        }
    }
}

AfterAll {
    Remove-Module -Name InfraPulse -Force -ErrorAction SilentlyContinue
}

Describe 'InfraPulse report import' {
    It 'round-trips an exported report with rehydrated types and timestamps' {
        $path = Join-Path -Path $TestDrive -ChildPath 'roundtrip.json'
        $script:Snapshots.Before | Export-InfraPulseReport -Path $path -Force

        $imported = Import-InfraPulseReport -Path $path

        $imported.PSObject.TypeNames | Should -Contain 'InfraPulse.Report'
        $imported.SchemaVersion | Should -Be '1.2'
        $imported.RunId | Should -Be '11111111-1111-4111-8111-111111111111'
        $imported.ConfigurationFingerprint | Should -Be 'fingerprint-a'
        $imported.GeneratedAtUtc | Should -BeOfType [datetime]
        $imported.StartedAtUtc | Should -BeOfType [datetime]
        @($imported.Results)[0].PSObject.TypeNames | Should -Contain 'InfraPulse.Result'
        @($imported.Results)[0].TimestampUtc | Should -BeOfType [datetime]
        @($imported.Results).Count | Should -Be 6
    }

    It 'imports a schema 1.0 report with legacy date encoding and upgrades its shape' {
        $legacyJson = @'
[
  {
    "SchemaVersion": "1.0",
    "Tool": "InfraPulse",
    "ToolVersion": "1.0.0",
    "RequestedComputerName": "legacy-01",
    "ComputerName": "LEGACY-01",
    "GeneratedAtUtc": "\/Date(1784539945812)\/",
    "OverallStatus": "Healthy",
    "Summary": { "Total": 1, "Healthy": 1, "Warning": 0, "Critical": 0, "Unknown": 0, "Skipped": 0 },
    "Inventory": null,
    "Results": [
      {
        "SchemaVersion": "1.0",
        "ComputerName": "LEGACY-01",
        "CheckName": "Memory",
        "Category": "Capacity",
        "Target": "Physical memory",
        "Status": "Healthy",
        "Message": "Fine.",
        "ObservedValue": "55.00%",
        "WarningThreshold": null,
        "CriticalThreshold": null,
        "Recommendation": "",
        "Evidence": {},
        "TimestampUtc": "\/Date(1784539945812)\/",
        "DurationMs": 1.0,
        "Error": ""
      }
    ],
    "Tags": [],
    "DurationMs": 10.0
  }
]
'@
        $path = Join-Path -Path $TestDrive -ChildPath 'legacy.json'
        Set-Content -LiteralPath $path -Value $legacyJson -Encoding UTF8

        $imported = Import-InfraPulseReport -Path $path

        $imported.PSObject.TypeNames | Should -Contain 'InfraPulse.Report'
        $imported.GeneratedAtUtc | Should -BeOfType [datetime]
        ([datetime]$imported.GeneratedAtUtc).Year | Should -Be 2026
        $imported.RunId | Should -Be ''
        $imported.ConfigurationFingerprint | Should -Be ''
        @($imported.Results)[0].TimestampUtc | Should -BeOfType [datetime]
    }

    It 'rejects JSON that is not an InfraPulse report' {
        $path = Join-Path -Path $TestDrive -ChildPath 'not-a-report.json'
        Set-Content -LiteralPath $path -Value '{ "Name": "something-else" }' -Encoding UTF8

        { Import-InfraPulseReport -Path $path } | Should -Throw '*not a valid InfraPulse report*'
    }

    It 'rejects an unsupported schema version' {
        $path = Join-Path -Path $TestDrive -ChildPath 'future-schema.json'
        Set-Content -LiteralPath $path -Value '{ "SchemaVersion": "9.0", "Tool": "InfraPulse", "ComputerName": "x", "OverallStatus": "Healthy", "Summary": {}, "Results": [] }' -Encoding UTF8

        { Import-InfraPulseReport -Path $path } | Should -Throw '*unsupported report schema version*'
    }
}

Describe 'InfraPulse snapshot comparison' {
    BeforeAll {
        $script:Comparison = Compare-InfraPulseReport -ReferenceObject $script:Snapshots.Before -DifferenceObject $script:Snapshots.After
    }

    It 'classifies every change type deterministically' {
        $changes = @($script:Comparison.Changes)
        $byKey = @{}
        foreach ($change in $changes) {
            $byKey["$($change.CheckName)|$($change.Target)"] = $change
        }

        $byKey['Disk|C:'].ChangeType | Should -Be 'Regressed'
        $byKey['Disk|D:'].ChangeType | Should -Be 'Resolved'
        $byKey['Services|Spooler'].ChangeType | Should -Be 'Improved'
        $byKey['Memory|Physical memory'].ChangeType | Should -Be 'Changed'
        $byKey['Uptime|Operating system'].ChangeType | Should -Be 'Unchanged'
        $byKey['Certificates|CN=app.contoso.invalid'].ChangeType | Should -Be 'NotComparable'
        $byKey['EventLog|Application'].ChangeType | Should -Be 'NewFinding'
        $byKey['Tcp|Portal'].ChangeType | Should -Be 'Added'
    }

    It 'summarizes change counts and regressions' {
        $summary = $script:Comparison.Summary
        $summary.Total | Should -Be 8
        $summary.NewFinding | Should -Be 1
        $summary.Regressed | Should -Be 1
        $summary.Resolved | Should -Be 1
        $summary.Improved | Should -Be 1
        $summary.Changed | Should -Be 1
        $summary.NotComparable | Should -Be 1
        $summary.Added | Should -Be 1
        $summary.Unchanged | Should -Be 1
        $script:Comparison.HasRegressions | Should -BeTrue
        $script:Comparison.Comparable | Should -BeTrue
    }

    It 'carries run metadata and configuration equivalence' {
        $script:Comparison.Reference.RunId | Should -Be '11111111-1111-4111-8111-111111111111'
        $script:Comparison.Difference.RunId | Should -Be '22222222-2222-4222-8222-222222222222'
        $script:Comparison.ConfigurationMatches | Should -BeTrue
    }

    It 'flags snapshots collected with different configurations' {
        $modifiedAfter = InModuleScope InfraPulse -Parameters @{ Source = $script:Snapshots.After } {
            param($Source)
            $clone = New-InfraPulseReport -RequestedComputerName $Source.RequestedComputerName -ComputerName $Source.ComputerName -Inventory $null -Results @($Source.Results) -DurationMs 100 -RunId 'run-x' -ConfigurationFingerprint 'fingerprint-b'
            $clone
        }

        $comparison = Compare-InfraPulseReport $script:Snapshots.Before $modifiedAfter
        $comparison.ConfigurationMatches | Should -BeFalse
    }

    It 'excludes unchanged entries on request while keeping the counts' {
        $filtered = Compare-InfraPulseReport $script:Snapshots.Before $script:Snapshots.After -ExcludeUnchanged

        @($filtered.Changes | Where-Object ChangeType -EQ 'Unchanged').Count | Should -Be 0
        @($filtered.Changes).Count | Should -Be 7
        $filtered.Summary.Unchanged | Should -Be 1
    }

    It 'rejects objects that are not reports' {
        { Compare-InfraPulseReport -ReferenceObject ([pscustomobject]@{ Name = 'x' }) -DifferenceObject $script:Snapshots.After } | Should -Throw '*must contain InfraPulse reports*'
    }
}

Describe 'InfraPulse policy evaluation' {
    It 'passes a report without blocking results under the default policy' {
        $evaluation = $script:Snapshots.Before | Test-InfraPulseReport -FailOn Critical -MaximumWarnings 2

        $evaluation.PSObject.TypeNames | Should -Contain 'InfraPulse.PolicyEvaluation'
        $evaluation.Passed | Should -BeFalse
        $evaluation.BlockingCount | Should -Be 1
        $evaluation.Blocking[0].CheckName | Should -Be 'Services'
    }

    It 'fails when warnings exceed the budget' {
        $evaluation = $script:Snapshots.After | Test-InfraPulseReport -FailOn Critical -MaximumWarnings 1

        $evaluation.Passed | Should -BeFalse
        $evaluation.WarningCount | Should -Be 2
        $evaluation.Message | Should -Match 'exceed the budget'
    }

    It 'passes when the warning budget is large enough and no blocking status remains' {
        $evaluation = $script:Snapshots.After | Test-InfraPulseReport -FailOn Unknown -MaximumWarnings 5

        $evaluation.Passed | Should -BeTrue
        $evaluation.BlockingCount | Should -Be 0
        $evaluation.WarningCount | Should -Be 2
    }

    It 'applies wildcard ignore rules from a policy file' {
        $policyPath = Join-Path -Path $TestDrive -ChildPath 'policy.psd1'
        Set-Content -LiteralPath $policyPath -Encoding UTF8 -Value @'
@{
    SchemaVersion = '1.0'
    FailOn = @('Critical', 'Unknown')
    MaximumWarnings = 5
    Ignore = @(
        @{
            CheckName = 'Disk'
            Target    = 'C*'
            Status    = 'Critical'
        }
    )
}
'@

        $evaluation = $script:Snapshots.After | Test-InfraPulseReport -PolicyPath $policyPath

        $evaluation.Passed | Should -BeTrue
        $evaluation.IgnoredCount | Should -Be 1
        $evaluation.PolicySource | Should -Match 'policy\.psd1'
    }

    It 'rejects an invalid policy file' {
        $policyPath = Join-Path -Path $TestDrive -ChildPath 'invalid-policy.psd1'
        Set-Content -LiteralPath $policyPath -Encoding UTF8 -Value @'
@{
    SchemaVersion = '1.0'
    FailOn = @('Fatal')
    Ignore = @(
        @{ Unsupported = 'x' }
    )
}
'@

        { $script:Snapshots.After | Test-InfraPulseReport -PolicyPath $policyPath } | Should -Throw '*invalid*'
    }

    It 'returns a Boolean with Quiet and throws only on request' {
        ($script:Snapshots.After | Test-InfraPulseReport -FailOn Critical -MaximumWarnings 0 -Quiet) | Should -BeFalse
        { $script:Snapshots.After | Test-InfraPulseReport -FailOn Critical -MaximumWarnings 0 -ThrowOnFailure } | Should -Throw '*Policy evaluation failed*'
        ($script:Snapshots.After | Test-InfraPulseReport -FailOn Unknown -MaximumWarnings 5 -Quiet) | Should -BeTrue
    }
}

Describe 'InfraPulse comparison gate' {
    BeforeAll {
        $script:GateComparison = Compare-InfraPulseReport -ReferenceObject $script:Snapshots.Before -DifferenceObject $script:Snapshots.After
        $script:CleanComparison = Compare-InfraPulseReport -ReferenceObject $script:Snapshots.Before -DifferenceObject $script:Snapshots.Before
    }

    It 'fails on new findings and regressions by default' {
        $evaluation = $script:GateComparison | Test-InfraPulseComparison

        $evaluation.PSObject.TypeNames | Should -Contain 'InfraPulse.ComparisonEvaluation'
        $evaluation.Passed | Should -BeFalse
        $evaluation.ViolationCount | Should -Be 2
        @($evaluation.Violations.ChangeType) | Should -Contain 'NewFinding'
        @($evaluation.Violations.ChangeType) | Should -Contain 'Regressed'
    }

    It 'passes an identical snapshot pair' {
        $evaluation = $script:CleanComparison | Test-InfraPulseComparison

        $evaluation.Passed | Should -BeTrue
        $evaluation.ViolationCount | Should -Be 0
    }

    It 'honors custom blocking change types' {
        $evaluation = $script:GateComparison | Test-InfraPulseComparison -FailOn NotComparable

        $evaluation.Passed | Should -BeFalse
        $evaluation.ViolationCount | Should -Be 1
        $evaluation.Violations[0].CheckName | Should -Be 'Certificates'
    }

    It 'returns a Boolean with Quiet and throws only on request' {
        ($script:GateComparison | Test-InfraPulseComparison -Quiet) | Should -BeFalse
        ($script:CleanComparison | Test-InfraPulseComparison -Quiet) | Should -BeTrue
        { $script:GateComparison | Test-InfraPulseComparison -ThrowOnFailure } | Should -Throw '*blocking change*'
    }

    It 'rejects objects that are not comparisons' {
        { [pscustomobject]@{ Name = 'x' } | Test-InfraPulseComparison } | Should -Throw '*not an InfraPulse comparison*'
    }
}

Describe 'InfraPulse comparison export' {
    BeforeAll {
        $script:ExportComparison = Compare-InfraPulseReport -ReferenceObject $script:Snapshots.Before -DifferenceObject $script:Snapshots.After
    }

    It 'writes a self-contained HTML change report' {
        $path = Join-Path -Path $TestDrive -ChildPath 'change.html'
        $file = $script:ExportComparison | Export-InfraPulseComparison -Path $path -Force -PassThru
        $content = Get-Content -LiteralPath $file.FullName -Raw

        $content | Should -Match '<!doctype html>'
        $content | Should -Match 'Regressed'
        $content | Should -Match 'SRV-CMP-01'
        $content | Should -Not -Match '<link[^>]+stylesheet'
        $content | Should -Not -Match '/Date\('
    }

    It 'writes one CSV row per change' {
        $path = Join-Path -Path $TestDrive -ChildPath 'change.csv'
        $script:ExportComparison | Export-InfraPulseComparison -Path $path -Force
        $rows = @(Import-Csv -LiteralPath $path)

        $rows.Count | Should -Be 8
        @($rows.ChangeType) | Should -Contain 'NewFinding'
        @($rows.ChangeType) | Should -Contain 'Unchanged'
    }

    It 'writes structured JSON without legacy date encoding' {
        $path = Join-Path -Path $TestDrive -ChildPath 'change.json'
        $script:ExportComparison | Export-InfraPulseComparison -Path $path -Force
        $raw = Get-Content -LiteralPath $path -Raw
        $data = @($raw | ConvertFrom-Json)

        $raw | Should -Not -Match '/Date\('
        $data[0].ComputerName | Should -Be 'SRV-CMP-01'
        @($data[0].Changes).Count | Should -Be 8
    }

    It 'rejects objects that are not comparisons' {
        { [pscustomobject]@{ Name = 'not-a-comparison' } | Export-InfraPulseComparison -Path (Join-Path $TestDrive 'invalid.html') } | Should -Throw '*not an InfraPulse comparison*'
    }
}
