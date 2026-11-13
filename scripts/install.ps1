# Copies the addon into the game's AddOns folder.
#   .\scripts\install.ps1
#   .\scripts\install.ps1 -Game "D:\Games\World of Warcraft"
param(
    [string]$Game = "C:\Program Files (x86)\World of Warcraft"
)

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root "UpgradeScout"
$addons = Join-Path $Game "_forever_\Interface\AddOns"
$target = Join-Path $addons "UpgradeScout"

if (-not (Test-Path $addons)) {
    Write-Error "AddOns folder not found: $addons"
    exit 1
}
if (-not (Test-Path (Join-Path $addons "Pawn"))) {
    Write-Warning "Pawn is not installed in $addons. Upgrade Scout will not load without it."
}

if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
}
Copy-Item -Recurse $source $target
Write-Host "Installed to $target"
Write-Host "Restart the game so it picks the addon up."
