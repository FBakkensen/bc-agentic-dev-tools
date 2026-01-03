#Requires -Version 7.2
<#
.SYNOPSIS
    Validates that each plugin has the required plugin.json file.
.DESCRIPTION
    Checks all directories under plugins/ and ensures each has a plugin.json file.
    Returns exit code 1 if any plugin is missing its plugin.json.
.EXAMPLE
    pwsh scripts/Validate-PluginStructure.ps1
#>
[CmdletBinding()]
param()

$pluginsPath = Join-Path $PSScriptRoot ".." "plugins"
$plugins = Get-ChildItem -Path $pluginsPath -Directory

$errors = @()
foreach ($plugin in $plugins) {
    $pluginJson = Join-Path $plugin.FullName "plugin.json"
    if (-not (Test-Path $pluginJson)) {
        $errors += "Missing plugin.json in $($plugin.Name)"
        Write-Host "FAIL: $($plugin.Name)/plugin.json missing" -ForegroundColor Red
    } else {
        Write-Host "OK: $($plugin.Name)/plugin.json exists" -ForegroundColor Green
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "`nAll plugins have valid structure." -ForegroundColor Cyan
