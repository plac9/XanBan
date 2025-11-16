Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptFiles = Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1 |
  Where-Object { $_.FullName -notmatch '\\releases\\' }

Describe "Repository layout" {
  It "contains PowerShell scripts" {
    $scriptFiles.Count | Should -BeGreaterThan 0
  }
}

Describe "Script syntax" {
  It "parses all PowerShell scripts without errors" {
    foreach ($script in $scriptFiles) {
      $tokens = $null
      $errors = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
      if ($errors) {
        $messages = ($errors | ForEach-Object { $_.Message }) -join "; "
        throw "Parsing failed for $($script.FullName): $messages"
      }
    }
  }
}
