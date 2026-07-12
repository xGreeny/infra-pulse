function New-InfraPulseResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'Warning', 'Critical', 'Unknown', 'Skipped')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$CheckName,

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [object]$ObservedValue,

        [AllowNull()]
        [object]$WarningThreshold,

        [AllowNull()]
        [object]$CriticalThreshold,

        [string]$Recommendation = '',

        [System.Collections.IDictionary]$Evidence = @{},

        [double]$DurationMs = 0,

        [string]$ErrorMessage = ''
    )

    $result = [pscustomobject][ordered]@{
        SchemaVersion     = '1.0'
        ComputerName      = $ComputerName
        CheckName         = $CheckName
        Category          = $Category
        Target            = $Target
        Status            = $Status
        Message           = $Message
        ObservedValue     = $ObservedValue
        WarningThreshold  = $WarningThreshold
        CriticalThreshold = $CriticalThreshold
        Recommendation    = $Recommendation
        Evidence          = $Evidence
        TimestampUtc      = [DateTime]::UtcNow
        DurationMs        = [math]::Round($DurationMs, 2)
        Error             = $ErrorMessage
    }
    $result.PSObject.TypeNames.Insert(0, 'InfraPulse.Result')
    return $result
}
