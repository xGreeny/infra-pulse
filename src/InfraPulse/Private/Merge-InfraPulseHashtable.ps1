function Merge-InfraPulseHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Base,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Override
    )

    $result = Copy-InfraPulseValue -Value $Base

    foreach ($key in $Override.Keys) {
        $overrideValue = $Override[$key]

        if (
            $result.Contains($key) -and
            $result[$key] -is [System.Collections.IDictionary] -and
            $overrideValue -is [System.Collections.IDictionary]
        ) {
            $result[$key] = Merge-InfraPulseHashtable -Base $result[$key] -Override $overrideValue
        }
        else {
            $result[$key] = Copy-InfraPulseValue -Value $overrideValue
        }
    }

    return $result
}
