#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$summaryPath = $env:GITHUB_STEP_SUMMARY

Write-Host "📁 Repository root: $repoRoot"

$scriptFiles = Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1 |
  Where-Object { $_.FullName -notmatch '\\releases\\' }

if (-not $scriptFiles) {
  Write-Host "No PowerShell files detected. Skipping validation."
  exit 0
}

Write-Host "🔎 ScriptAnalyzer - scanning $($scriptFiles.Count) scripts..."
$analysis = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Severity Error
if ($analysis) {
  $analysis | Format-Table -AutoSize
  throw "ScriptAnalyzer reported blocking issues."
}

Write-Host "🧪 Running Pester smoke tests..."
Invoke-Pester -CI -Output Detailed

if ($summaryPath) {
  @"
## PowerShell validation
- Scripts scanned: $($scriptFiles.Count)
- ScriptAnalyzer: 0 blocking issues
- Tests: Completed via Invoke-Pester
"@ >> $summaryPath
}
