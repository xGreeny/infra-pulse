function Import-InfraPulseChangePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
        throw "Policy files must use the .psd1 extension: '$resolvedPath'."
    }

    $policyData = Import-PowerShellDataFile -Path $resolvedPath
    $errors = New-Object System.Collections.Generic.List[string]
    $validStatuses = @('Healthy', 'Warning', 'Critical', 'Unknown', 'Skipped')
    $validIgnoreKeys = @('ComputerName', 'CheckName', 'Category', 'Target', 'Status')

    if (-not $policyData.Contains('SchemaVersion')) {
        [void]$errors.Add('SchemaVersion is required.')
    }
    elseif ([string]$policyData.SchemaVersion -ne '1.0') {
        [void]$errors.Add("Unsupported policy SchemaVersion '$($policyData.SchemaVersion)'. Supported version: 1.0.")
    }

    $failOn = @('Critical', 'Unknown')
    if ($policyData.Contains('FailOn')) {
        $failOn = @($policyData.FailOn | ForEach-Object { [string]$_ } | Select-Object -Unique)
        if ($failOn.Count -eq 0) {
            [void]$errors.Add('FailOn cannot be empty when specified.')
        }
        foreach ($status in $failOn) {
            if ($status -notin $validStatuses) {
                [void]$errors.Add("FailOn contains invalid status '$status'.")
            }
        }
    }

    $maximumWarnings = 0
    if ($policyData.Contains('MaximumWarnings')) {
        if (-not (Test-InfraPulseNumber -Value $policyData.MaximumWarnings -Minimum 0)) {
            [void]$errors.Add('MaximumWarnings must be zero or greater.')
        }
        else {
            $maximumWarnings = [int]$policyData.MaximumWarnings
        }
    }

    $ignoreRules = @()
    if ($policyData.Contains('Ignore')) {
        $index = 0
        foreach ($rule in @($policyData.Ignore)) {
            if (-not ($rule -is [System.Collections.IDictionary])) {
                [void]$errors.Add("Ignore[$index] must be a hashtable.")
            }
            else {
                $populatedKeys = 0
                foreach ($key in $rule.Keys) {
                    if ([string]$key -notin $validIgnoreKeys) {
                        [void]$errors.Add("Ignore[$index] contains unsupported key '$key'. Supported keys: $($validIgnoreKeys -join ', ').")
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace([string]$rule[$key])) {
                        $populatedKeys++
                    }
                }
                if ($populatedKeys -eq 0) {
                    [void]$errors.Add("Ignore[$index] must populate at least one field.")
                }
                else {
                    $ignoreRules += , $rule
                }
            }
            $index++
        }
    }

    if ($errors.Count -gt 0) {
        $message = "Policy file '$resolvedPath' is invalid:" + [Environment]::NewLine + (($errors | ForEach-Object { " - $_" }) -join [Environment]::NewLine)
        throw $message
    }

    [pscustomobject]@{
        FailOn          = $failOn
        MaximumWarnings = $maximumWarnings
        Ignore          = @($ignoreRules)
    }
}

function Test-InfraPulseIgnoreRuleMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Result,

        [AllowEmptyCollection()]
        [object[]]$Rules = @()
    )

    foreach ($rule in @($Rules)) {
        $allFieldsMatch = $true
        $hasPopulatedField = $false

        foreach ($fieldName in @('ComputerName', 'CheckName', 'Category', 'Target', 'Status')) {
            if (-not $rule.Contains($fieldName) -or [string]::IsNullOrWhiteSpace([string]$rule[$fieldName])) {
                continue
            }
            $hasPopulatedField = $true
            if ([string]$Result.$fieldName -notlike [string]$rule[$fieldName]) {
                $allFieldsMatch = $false
                break
            }
        }

        if ($hasPopulatedField -and $allFieldsMatch) {
            return $true
        }
    }

    return $false
}
