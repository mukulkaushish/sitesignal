param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $PSScriptRoot
$hostArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($hostArchitecture -ne $Architecture) {
    throw "Flutter Windows builds must match the host architecture. Requested $Architecture on $hostArchitecture."
}

$artifactArchitecture = if ($Architecture -eq "x64") { "x86_64" } else { "arm64" }
$bundle = Join-Path $projectDir "build\windows\$Architecture\runner\Release"
$outputDir = Join-Path $projectDir "build\distributions\windows\$artifactArchitecture"
$outputBundle = Join-Path $outputDir "SiteSignal"
$outputArchive = Join-Path $outputDir "SiteSignal-windows-$artifactArchitecture.zip"
$msixArchive = Join-Path $outputDir "SiteSignal-windows-$artifactArchitecture.msix"
$symbolsDir = Join-Path $projectDir "build\debug-symbols\windows\$artifactArchitecture"

Set-Location $projectDir
flutter build windows --release --split-debug-info=$symbolsDir
if ($LASTEXITCODE -ne 0) {
    throw "Flutter failed to build the Windows release."
}

if (-not (Test-Path -Path $bundle -PathType Container)) {
    throw "Flutter did not create the expected bundle: $bundle"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
if (Test-Path $outputBundle) {
    Remove-Item -Path $outputBundle -Recurse -Force
}
if (Test-Path $outputArchive) {
    Remove-Item -Path $outputArchive -Force
}
if (Test-Path $msixArchive) {
    Remove-Item -Path $msixArchive -Force
}
Copy-Item -Path $bundle -Destination $outputBundle -Recurse

$executable = Join-Path $outputBundle "site_signal.exe"
$sqliteRuntime = Join-Path $outputBundle "sqlite3.dll"
if (-not (Test-Path -Path $executable -PathType Leaf)) {
    throw "SiteSignal executable is missing from the Windows bundle."
}
if (-not (Test-Path -Path $sqliteRuntime -PathType Leaf)) {
    throw "Bundled SQLite runtime is missing from the Windows release."
}

Compress-Archive -Path (Join-Path $outputBundle "*") -DestinationPath $outputArchive
dart run msix:create `
    --architecture $Architecture `
    --output-path $outputDir `
    --output-name "SiteSignal-windows-$artifactArchitecture"
if ($LASTEXITCODE -ne 0) {
    throw "MSIX packaging failed."
}
if (-not (Test-Path -Path $msixArchive -PathType Leaf)) {
    throw "MSIX packaging did not create the expected installer: $msixArchive"
}

$bundleSize = (Get-ChildItem $outputBundle -Recurse -File |
    Measure-Object -Property Length -Sum).Sum
$archiveSize = (Get-Item $outputArchive).Length
$msixSize = (Get-Item $msixArchive).Length
Write-Host ("Bundle:  {0:N1} MiB" -f ($bundleSize / 1MB))
Write-Host ("Archive: {0:N1} MiB" -f ($archiveSize / 1MB))
Write-Host ("MSIX:    {0:N1} MiB" -f ($msixSize / 1MB))
Write-Host $outputArchive
Write-Host $msixArchive
