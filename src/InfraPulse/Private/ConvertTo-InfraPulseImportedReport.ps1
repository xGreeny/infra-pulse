function ConvertTo-InfraPulseImportedReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [string]$Source
    )

    if ($null -eq $Entry) {
        throw "File '$Source' contains a null entry and cannot be imported as an InfraPulse report."
    }

    foreach ($requiredProperty in @('SchemaVersion', 'Tool', 'ComputerName', 'OverallStatus', 'Summary', 'Results')) {
        if ($null -eq $Entry.PSObject.Properties[$requiredProperty]) {
            throw "File '$Source' is not a valid InfraPulse report: property '$requiredProperty' is missing."
        }
    }

    if ([string]$Entry.Tool -ne 'InfraPulse') {
        throw "File '$Source' is not a valid InfraPulse report: Tool is '$($Entry.Tool)'."
    }

    $schemaVersion = [string]$Entry.SchemaVersion
    if ($schemaVersion -notin @('1.0', '1.1')) {
        throw "File '$Source' uses unsupported report schema version '$schemaVersion'. Supported versions: 1.0, 1.1."
    }

    foreach ($dateProperty in @('GeneratedAtUtc', 'StartedAtUtc', 'CompletedAtUtc')) {
        $property = $Entry.PSObject.Properties[$dateProperty]
        if ($null -ne $property) {
            $property.Value = ConvertFrom-InfraPulseJsonDate -Value $property.Value
        }
    }

    # Schema 1.0 reports gain the 1.1 fields with empty values so consumers can
    # rely on one shape regardless of the source schema.
    foreach ($schemaField in @('RunId', 'ConfigurationFingerprint')) {
        if ($null -eq $Entry.PSObject.Properties[$schemaField]) {
            Add-Member -InputObject $Entry -NotePropertyName $schemaField -NotePropertyValue ''
        }
    }
    foreach ($schemaField in @('StartedAtUtc', 'CompletedAtUtc')) {
        if ($null -eq $Entry.PSObject.Properties[$schemaField]) {
            Add-Member -InputObject $Entry -NotePropertyName $schemaField -NotePropertyValue $null
        }
    }

    if ($null -ne $Entry.Inventory -and $null -ne $Entry.Inventory.PSObject.Properties['CollectedAtUtc']) {
        $Entry.Inventory.PSObject.Properties['CollectedAtUtc'].Value = ConvertFrom-InfraPulseJsonDate -Value $Entry.Inventory.CollectedAtUtc
    }

    foreach ($result in @($Entry.Results)) {
        if ($null -eq $result) {
            continue
        }
        $timestampProperty = $result.PSObject.Properties['TimestampUtc']
        if ($null -ne $timestampProperty) {
            $timestampProperty.Value = ConvertFrom-InfraPulseJsonDate -Value $timestampProperty.Value
        }
        if ($result.PSObject.TypeNames -notcontains 'InfraPulse.Result') {
            $result.PSObject.TypeNames.Insert(0, 'InfraPulse.Result')
        }
    }

    if ($Entry.PSObject.TypeNames -notcontains 'InfraPulse.Report') {
        $Entry.PSObject.TypeNames.Insert(0, 'InfraPulse.Report')
    }

    return $Entry
}

function ConvertFrom-InfraPulseJsonDate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime()
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    # Windows PowerShell 5.1 exported DateTime values as "\/Date(<epoch-ms>)\/"
    # before schema 1.1 normalized every export to ISO 8601.
    if ($text -match '^\\?/Date\((-?\d+)\)\\?/$') {
        $epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        return $epoch.AddMilliseconds([double]$Matches[1])
    }

    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    return $Value
}
