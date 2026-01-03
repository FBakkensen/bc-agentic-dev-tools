#Requires -Version 7.2
<#
.SYNOPSIS
    Validates PowerShell syntax for all .ps1 files in the repository.
.DESCRIPTION
    Recursively finds all .ps1 files and validates their syntax using the PowerShell parser.
    Returns exit code 1 if any file fails validation.
.EXAMPLE
    pwsh scripts/Validate-PowerShell.ps1
#>
[CmdletBinding()]
param()

$errors = @()
Get-ChildItem -Path $PSScriptRoot/.. -Recurse -Filter "*.ps1" | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $errors += "FAIL: $($_.FullName)"
        $parseErrors | ForEach-Object { $errors += "  - $($_.Message)" }
        Write-Host "FAIL: $($_.FullName)" -ForegroundColor Red
    } else {
        Write-Host "OK: $($_.FullName)" -ForegroundColor Green
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "`nAll PowerShell files validated successfully." -ForegroundColor Cyan
