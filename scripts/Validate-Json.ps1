#Requires -Version 7.2
<#
.SYNOPSIS
    Validates JSON syntax for all .json files in the repository.
.DESCRIPTION
    Recursively finds all .json files and validates their syntax using ConvertFrom-Json.
    Returns exit code 1 if any file fails validation.
.EXAMPLE
    pwsh scripts/Validate-Json.ps1
#>
[CmdletBinding()]
param()

$errors = @()
Get-ChildItem -Path $PSScriptRoot/.. -Recurse -Filter "*.json" | ForEach-Object {
    try {
        $null = Get-Content $_.FullName -Raw | ConvertFrom-Json
        Write-Host "OK: $($_.FullName)" -ForegroundColor Green
    } catch {
        $errors += "FAIL: $($_.FullName) - $($_.Exception.Message)"
        Write-Host "FAIL: $($_.FullName)" -ForegroundColor Red
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "`nAll JSON files validated successfully." -ForegroundColor Cyan
