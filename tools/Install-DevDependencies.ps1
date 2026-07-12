[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
& (Join-Path -Path $repositoryRoot -ChildPath 'build.ps1') -Task Analyze -Bootstrap
