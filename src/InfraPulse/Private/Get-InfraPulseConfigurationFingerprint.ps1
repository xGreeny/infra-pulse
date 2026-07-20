function Get-InfraPulseConfigurationFingerprint {
    # The fingerprint must be identical for logically equal configurations across
    # PowerShell editions, so the canonical form uses sorted dictionary keys and
    # invariant-culture scalar formatting instead of ConvertTo-Json.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Configuration
    )

    function ConvertTo-CanonicalText {
        param(
            [AllowNull()]
            [object]$Value
        )

        if ($null -eq $Value) {
            return '<null>'
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $pairs = foreach ($key in @($Value.Keys | Sort-Object -Property { [string]$_ })) {
                '{0}={1}' -f [string]$key, (ConvertTo-CanonicalText -Value $Value[$key])
            }
            return '{' + ($pairs -join ';') + '}'
        }

        if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
            $items = foreach ($item in $Value) {
                ConvertTo-CanonicalText -Value $item
            }
            return '[' + ($items -join ',') + ']'
        }

        if ($Value -is [bool]) {
            return ([bool]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }

        if ($Value -is [datetime]) {
            return $Value.ToUniversalTime().ToString('o')
        }

        return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
    }

    $canonical = ConvertTo-CanonicalText -Value $Configuration
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonical))
    }
    finally {
        $sha256.Dispose()
    }

    return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
