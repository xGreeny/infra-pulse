function ConvertTo-InfraPulseSerializableValue {
    # ConvertTo-Json serializes DateTime as "\/Date(...)\/" on Windows PowerShell 5.1 but as ISO 8601 on
    # PowerShell 7, so all DateTime values must be normalized to round-trip UTC strings before serialization.
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('o')
    }

    if ($Value -is [System.DateTimeOffset]) {
        return $Value.UtcDateTime.ToString('o')
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[$key] = ConvertTo-InfraPulseSerializableValue -Value $Value[$key]
        }
        return , $copy
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-InfraPulseSerializableValue -Value $item))
        }
        return , $items.ToArray()
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $copy[$property.Name] = ConvertTo-InfraPulseSerializableValue -Value $property.Value
        }
        return [pscustomobject]$copy
    }

    return $Value
}
