Set-StrictMode -Version Latest

$script:InfraPulseModuleRoot = $PSScriptRoot
$script:InfraPulseManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'InfraPulse.psd1'
$script:InfraPulseModuleVersion = (Import-PowerShellDataFile -Path $script:InfraPulseManifestPath).ModuleVersion

$privateScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File | Sort-Object -Property Name
$publicScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File | Sort-Object -Property Name

foreach ($scriptFile in @($privateScripts) + @($publicScripts)) {
    try {
        . $scriptFile.FullName
    }
    catch {
        throw "Failed to load InfraPulse script '$($scriptFile.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicScripts.BaseName
