[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory=$true)][string]$TargetUsername,
  [Parameter(Mandatory=$true)][string]$AllowedStart,   # e.g., "07:00"
  [Parameter(Mandatory=$true)][string]$AllowedEnd,     # e.g., "21:00"
  [int[]]$WarnMinutesBefore = @(15,5,1),
  [int]$FinalWarningSeconds = 30,
  [int]$LogoffGraceSeconds = 30,
  [string]$InstallDir = "C:\ProgramData\XanBan"
)

function Write-Info($m){ Write-Host "[XanBan] $m" -ForegroundColor Cyan }

# Ensure elevated
$wi = [Security.Principal.WindowsIdentity]::GetCurrent()
$wp = New-Object Security.Principal.WindowsPrincipal($wi)
if (-not $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Please run this script in an elevated PowerShell session (Run as Administrator)."
}

# Validate times
try {
  [TimeSpan]::ParseExact($AllowedStart, @("hh\:mm","h\:mm"), $null) | Out-Null
  [TimeSpan]::ParseExact($AllowedEnd, @("hh\:mm","h\:mm"), $null)   | Out-Null
} catch {
  throw "AllowedStart/AllowedEnd must be in HH:mm format (e.g., 07:00)."
}

# Paths
$scriptSource = Join-Path $PSScriptRoot "XanBan.ps1"
if (-not (Test-Path $scriptSource)) {
  throw "Could not find XanBan.ps1 next to this installer. Ensure you run from the repo's scripts directory."
}

# Create install dir
if (-not (Test-Path $InstallDir)) {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
# Copy script
Copy-Item -Path $scriptSource -Destination (Join-Path $InstallDir "XanBan.ps1") -Force

# Write config
$configPath = Join-Path $InstallDir "config.json"
$config = [pscustomobject]@{
  TargetUsername     = $TargetUsername
  AllowedWindows     = @(@{ Start = $AllowedStart; End = $AllowedEnd })
  WarnMinutesBefore  = $WarnMinutesBefore
  FinalWarningSeconds= $FinalWarningSeconds
  LogoffGraceSeconds = $LogoffGraceSeconds
}
$config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

Write-Info "Installed script and config to $InstallDir"

# Register Scheduled Task
$taskName = "XanBan Enforcer"
$exe = "PowerShell.exe"
$args = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\XanBan.ps1`" -ConfigPath `"$configPath`""

$action   = New-ScheduledTaskAction -Execute $exe -Argument $args
$startup  = New-ScheduledTaskTrigger -AtStartup
$everyMin = New-ScheduledTaskTrigger -Daily -At 0:00 -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -AllowHardTerminate -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -Hidden

# Remove existing if present
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
  Start-Sleep -Seconds 1
}

Register-ScheduledTask -TaskName $taskName -Description "Enforces time limits for $TargetUsername (warns, logs off, disables, re-enables at allowed times)." `
  -Action $action -Trigger @($startup, $everyMin) -Principal $principal -Settings $settings | Out-Null

Write-Info "Scheduled Task '$taskName' created to run at startup and every 1 minute as SYSTEM."
Write-Info "Setup complete. You can test with: `"$exe $args -OverrideNow '2025-01-01T20:59:00'`""