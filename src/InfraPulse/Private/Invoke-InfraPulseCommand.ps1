function Invoke-InfraPulseCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @()
    )

    if ($null -ne $Context.Session) {
        return Invoke-Command -Session $Context.Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }

    return & $ScriptBlock @ArgumentList
}
