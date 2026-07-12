function Test-InfraPulseNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [double]$Minimum = [double]::MinValue,

        [double]$Maximum = [double]::MaxValue
    )

    if ($null -eq $Value) {
        return $false
    }

    $number = 0.0
    $text = [string]$Value
    $styles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
    $parsed = [double]::TryParse($text, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)
    if (-not $parsed) {
        $parsed = [double]::TryParse($text, $styles, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$number)
    }

    if (-not $parsed -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        return $false
    }

    return ($number -ge $Minimum -and $number -le $Maximum)
}
