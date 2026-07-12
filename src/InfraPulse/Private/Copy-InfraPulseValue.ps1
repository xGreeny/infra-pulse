function Copy-InfraPulseValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[$key] = Copy-InfraPulseValue -Value $Value[$key]
        }
        return $copy
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += , (Copy-InfraPulseValue -Value $item)
        }
        return $items
    }

    return $Value
}
