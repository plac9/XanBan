[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$InstallDir = "C:\ProgramData\XanBan",
  [switch]$RemoveFiles
)

$taskName = "XanBan Enforcer"

try {
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    Write-Host "Unregistered scheduled task '$taskName'."
  } else {
    Write-Host "Scheduled task '$taskName' not found."
  }
} catch {
  Write-Warning "Failed to unregister scheduled task: $($_.Exception.Message)"
}

if ($RemoveFiles) {
  try {
    if (Test-Path $InstallDir) {
      Remove-Item -Path $InstallDir -Recurse -Force
      Write-Host "Removed install directory $InstallDir."
    }
  } catch {
    Write-Warning "Failed to remove files: $($_.Exception.Message)"
  }
}