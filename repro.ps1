<#
.SYNOPSIS
    Reproduces the MethodBoundaryAspect.Fody runtime failure for .NET Framework assemblies
    woven under Core MSBuild ('dotnet build').

.DESCRIPTION
    For each build host (dotnet build = Core MSBuild, MSBuild.exe = .NET Framework MSBuild) this script
      1. deletes bin/obj,
      2. builds Repro.sln,
      3. reports whether each woven assembly references System.Private.CoreLib,
      4. runs the net48 and net8.0 apps.

.PARAMETER Build
    Which build host(s) to use: dotnet, msbuild or both (default).

.PARAMETER MethodBoundaryAspectFodyVersion
    Optional MethodBoundaryAspect.Fody package version to test instead of the default in Directory.Build.props.

.EXAMPLE
    ./repro.ps1
    ./repro.ps1 -Build dotnet
#>
[CmdletBinding()]
param(
    [ValidateSet('dotnet', 'msbuild', 'both')]
    [string] $Build = 'both',

    [string] $Configuration = 'Release',

    [string] $MethodBoundaryAspectFodyVersion
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$solution = Join-Path $root 'Repro.sln'

$versionArgs = @()
if ($MethodBoundaryAspectFodyVersion) {
    $versionArgs = @("-p:MethodBoundaryAspectFodyVersion=$MethodBoundaryAspectFodyVersion")
}

function Write-Header([string] $text) {
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-Host $text -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor Cyan
}

function Remove-BuildOutput {
    Get-ChildItem (Join-Path $root 'src') -Directory -Recurse -Include bin, obj |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-MSBuildExe {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found. Visual Studio or Build Tools are required for the MSBuild.exe run.' }

    $msbuild = & $vswhere -latest -prerelease -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
        Select-Object -First 1
    if (-not $msbuild) { throw 'MSBuild.exe not found.' }
    return $msbuild
}

function Invoke-Build([string] $host_) {
    if ($host_ -eq 'dotnet') {
        & dotnet build $solution -c $Configuration -nologo -v:m @versionArgs
    }
    else {
        $msbuild = Get-MSBuildExe
        Write-Host "MSBuild.exe: $msbuild"
        & $msbuild $solution -restore "-p:Configuration=$Configuration" -nologo -v:m @versionArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "Build with '$host_' failed." }
}

# Metadata names are stored as UTF-8 in the #Strings heap, so a byte search is enough for this check.
function Test-ReferencesPrivateCoreLib([string] $path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    return $text.Contains('System.Private.CoreLib')
}

function Invoke-App([string] $name, [string] $path) {
    Write-Host ''
    Write-Host "--- $name" -ForegroundColor Yellow
    if ($path.EndsWith('.dll')) { & dotnet $path | Out-Host } else { & $path | Out-Host }
    return $LASTEXITCODE -eq 0
}

$outNet48 = Join-Path $root "src\Repro.Net48\bin\$Configuration\net48"
$outNet8 = Join-Path $root "src\Repro.Net8\bin\$Configuration\net8.0"

$hosts = if ($Build -eq 'both') { @('dotnet', 'msbuild') } else { @($Build) }
$summary = @()

foreach ($h in $hosts) {
    $label = if ($h -eq 'dotnet') { 'dotnet build (Core MSBuild)' } else { 'MSBuild.exe (.NET Framework MSBuild)' }
    Write-Header "Build host: $label"

    Remove-BuildOutput
    Invoke-Build $h

    Write-Host ''
    Write-Host 'Woven assemblies referencing System.Private.CoreLib:' -ForegroundColor Yellow
    foreach ($file in @(
            (Join-Path $outNet48 'Repro.Net48.exe'),
            (Join-Path $outNet48 'Repro.Library.dll'),
            (Join-Path $outNet8 'Repro.Net8.dll'))) {
        $relative = $file.Substring($root.Length + 1)
        Write-Host ('    {0,-5} {1}' -f (Test-ReferencesPrivateCoreLib $file), $relative)
    }

    $net48Ok = Invoke-App 'net48 app (runs on .NET Framework)' (Join-Path $outNet48 'Repro.Net48.exe')
    $net8Ok = Invoke-App 'net8.0 app (runs on .NET 8)' (Join-Path $outNet8 'Repro.Net8.dll')

    $summary += [pscustomobject]@{ 'Build host' = $label; 'net48 app' = $(if ($net48Ok) { 'OK' } else { 'FAILED' }); 'net8.0 app' = $(if ($net8Ok) { 'OK' } else { 'FAILED' }) }
}

Write-Header 'Summary'
$summary | Format-Table -AutoSize | Out-String | Write-Host
