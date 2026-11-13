# Builds the archive players download: dist\UpgradeScout-<version>.zip, with the UpgradeScout
# folder at its top, ready to be unpacked into Interface\AddOns. The version comes from the .toc.
#   .\scripts\release.ps1
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root "UpgradeScout"
$toc = Join-Path $source "UpgradeScout.toc"
$version = (Select-String -Path $toc -Pattern '^## Version:\s*(\S+)').Matches[0].Groups[1].Value
if (-not $version) {
    Write-Error "No '## Version:' line in $toc"
    exit 1
}

$dist = Join-Path $root "dist"
$zip = Join-Path $dist "UpgradeScout-$version.zip"
New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip }

# Entry names are written by hand with forward slashes: archives with backslashes do not unpack
# into folders outside Windows.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = Get-ChildItem $source -Recurse -File | Sort-Object FullName
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\', '/').Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, "UpgradeScout/$relative",
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

Write-Host "Built $zip ($($files.Count) files, version $version)"
