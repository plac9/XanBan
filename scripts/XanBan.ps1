[CmdletBinding()]
param(
  [string]$ConfigPath = "C:\ProgramData\XanBan\config.json",
  [string]$StatePath  = "C:\ProgramData\XanBan\state.json",
  [string]$LogPath    = "C:\ProgramData\XanBan\XanBan.log",
  [string]$OverrideNow # ISO 8601 like "2025-08-10T20:45:00"
)

# ----------------------------------------
# Helpers
# ----------------------------------------

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts][$Level] $Message"
  try {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $line
  } catch { }
  Write-Output $line
}

function Ensure-AdminContext {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Log "Not running as Administrator/SYSTEM. Exiting." "ERROR"
    exit 1
  }
}

function Load-JsonFile {
  param([string]$Path, $Default = $null)
  if (-not (Test-Path $Path)) { return $Default }
  try {
    $content = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($content)) { return $Default }
    return $content | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Write-Log "Failed to parse JSON file: $Path. Error: $($_.Exception.Message)" "ERROR"
    return $Default
  }
}

function Save-JsonFile {
  param([string]$Path, [Parameter(ValueFromPipeline=$true)]$Object)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $json = $Object | ConvertTo-Json -Depth 6
  Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Parse-Time {
  param([string]$hhmm)
  # Accepts "HH:mm" or "H:mm"
  try {
    [TimeSpan]::ParseExact($hhmm, @("hh\:mm","h\:mm"), $null)
  } catch {
    throw "Invalid time format '$hhmm'. Use HH:mm."
  }
}

function Get-AllowedWindowsForNow {
  param(
    [DateTime]$Now,
    [object[]]$AllowedWindows # array of @{ Start="HH:mm"; End="HH:mm" }
  )
  # Returns a hashtable with:
  # - InsideWindow: bool
  # - CurrentWindow: @{Start=[DateTime]; End=[DateTime]} or $null
  # - NextStart: [DateTime] or $null
  # - AllWindows: list of windows considered
  $today = $Now.Date
  $yesterday = $today.AddDays(-1)
  $tomorrow = $today.AddDays(1)
  $windows = New-Object System.Collections.Generic.List[object]

  foreach ($w in $AllowedWindows) {
    $tsStart = Parse-Time $w.Start
    $tsEnd   = Parse-Time $w.End
    if ($tsStart -le $tsEnd) {
      # Same-day window
      $start = $today + $tsStart
      $end   = $today + $tsEnd
      $windows.Add([pscustomobject]@{ Start = $start; End = $end })
      # Also consider tomorrow's window for finding next start
      $windows.Add([pscustomobject]@{ Start = $tomorrow + $tsStart; End = $tomorrow + $tsEnd })
    } else {
      # Wraps midnight: yesterday->today and today->tomorrow
      $startYT = $yesterday + $tsStart
      $endYT   = $today + $tsEnd
      $windows.Add([pscustomobject]@{ Start = $startYT; End = $endYT })
      $startTT = $today + $tsStart
      $endTT   = $tomorrow + $tsEnd
      $windows.Add([pscustomobject]@{ Start = $startTT; End = $endTT })
      # Also include tomorrow->day+2 for future start discovery
      $startTM = $tomorrow + $tsStart
      $endTM   = $tomorrow.AddDays(1) + $tsEnd
      $windows.Add([pscustomobject]@{ Start = $startTM; End = $endTM })
    }
  }

  # Deduplicate overlapping potential duplicates (not strictly necessary)
  $windows = $windows | Sort-Object Start, End

  $inside = $false
  $current = $null
  foreach ($win in $windows) {
    if ($Now -ge $win.Start -and $Now -lt $win.End) {
      $inside = $true
      $current = $win
      break
    }
  }

  $nextStart = ($windows | Where-Object { $_.Start -gt $Now } | Sort-Object Start | Select-Object -First 1).Start

  return @{
    InsideWindow = $inside
    CurrentWindow = $current
    NextStart = $nextStart
    AllWindows = $windows
  }
}

function Get-LocalUserSafe {
  param([string]$UserName)
  try {
    return Get-LocalUser -Name $UserName -ErrorAction Stop
  } catch {
    return $null
  }
}

function Is-UserInAdministrators {
  param([string]$UserName)
  try {
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | Select-Object -ExpandProperty Name
    return $admins -contains $UserName -or ($admins | Where-Object { $_ -like "*\$UserName" }) # basic check
  } catch {
    return $false
  }
}

function Ensure-UserEnabled {
  param([string]$UserName)
  try {
    # Prefer LocalAccounts module
    $lu = Get-LocalUserSafe -UserName $UserName
    if ($lu -and -not $lu.Enabled) {
      Enable-LocalUser -Name $UserName -ErrorAction Stop
      Write-Log "Enabled user '$UserName'."
    } elseif (-not $lu) {
      # Fallback to net user
      cmd /c "net user `"$UserName`" /active:yes" | Out-Null
      Write-Log "Enabled user '$UserName' via 'net user' (user may be Microsoft account)."
    }
  } catch {
    # Fallback
    try {
      cmd /c "net user `"$UserName`" /active:yes" | Out-Null
      Write-Log "Enabled user '$UserName' via 'net user' fallback."
    } catch {
      Write-Log "Failed to enable user '$UserName': $($_.Exception.Message)" "ERROR"
    }
  }
}

function Ensure-UserDisabled {
  param([string]$UserName)
  try {
    $lu = Get-LocalUserSafe -UserName $UserName
    if ($lu -and $lu.Enabled) {
      Disable-LocalUser -Name $UserName -ErrorAction Stop
      Write-Log "Disabled user '$UserName'."
    } elseif (-not $lu) {
      # Fallback to net user
      cmd /c "net user `"$UserName`" /active:no" | Out-Null
      Write-Log "Disabled user '$UserName' via 'net user' (user may be Microsoft account)."
    }
  } catch {
    try {
      cmd /c "net user `"$UserName`" /active:no" | Out-Null
      Write-Log "Disabled user '$UserName' via 'net user' fallback."
    } catch {
      Write-Log "Failed to disable user '$UserName': $($_.Exception.Message)" "ERROR"
    }
  }
}

function Get-UserSessionIds {
  param([string]$UserName)
  # Uses 'query user' (quser) and parses session IDs for the user
  try {
    $output = & query user "$UserName" 2>$null
    if (-not $output) { return @() }
    $lines = $output | Select-Object -Skip 1
    $ids = @()
    foreach ($line in $lines) {
      $clean = ($line -replace '^\>', '').Trim()
      if (-not $clean) { continue }
      # Normalize whitespace, then split
      $parts = ($clean -replace '\s+',' ').Split(' ')
      # Typical columns: USERNAME, SESSIONNAME, ID, STATE, IDLE TIME, LOGON TIME (SESSIONNAME may be blank)
      # We assume ID is the 3rd token (index 2). If SESSIONNAME blank, quser usually pads, but our normalization collapses it.
      # A safer parse: find the first integer token.
      $id = $null
      foreach ($p in $parts) {
        if ($p -match '^\d+$') { $id = [int]$p; break }
      }
      if ($id -ne $null) { $ids += $id }
    }
    return $ids | Select-Object -Unique
  } catch {
    Write-Log "Failed to query sessions for '$UserName': $($_.Exception.Message)" "ERROR"
    return @()
  }
}

function Send-WarningMessage {
  param([int[]]$SessionIds, [string]$Message)
  foreach ($id in $SessionIds) {
    try {
      & msg $id $Message 2>$null
    } catch {
      # Ignore errors if session just ended
    }
  }
}

function Logoff-UserSessions {
  param([int[]]$SessionIds)
  foreach ($id in $SessionIds) {
    try {
      & logoff $id /V 2>$null
      Write-Log "Logged off session ID $id."
    } catch {
      # Ignore errors if already gone
    }
  }
}

function Get-Mutex {
  param([string]$Name)
  $globalName = "Global\$Name"
  return New-Object System.Threading.Mutex($false, $globalName)
}

# ----------------------------------------
# Main
# ----------------------------------------

Ensure-AdminContext

# Ensure directories exist
$programDataDir = "C:\ProgramData\XanBan"
if (-not (Test-Path $programDataDir)) { New-Item -ItemType Directory -Path $programDataDir -Force | Out-Null }

# Load config
$config = Load-JsonFile -Path $ConfigPath
if (-not $config) {
  # Seed a default config if missing
  $default = [pscustomobject]@{
    TargetUsername     = "ChildUser"
    AllowedWindows     = @(@{ Start = "07:00"; End = "21:00" })
    WarnMinutesBefore  = @(15, 5, 1)
    FinalWarningSeconds= 30
    LogoffGraceSeconds = 30
  }
  $default | Save-JsonFile -Path $ConfigPath
  Write-Log "No config found. Created default config at $ConfigPath. Please edit and rerun." "ERROR"
  exit 1
}

# Validate config
if (-not $config.TargetUsername -or -not $config.AllowedWindows -or $config.AllowedWindows.Count -eq 0) {
  Write-Log "Invalid config. Ensure TargetUsername and AllowedWindows are set in $ConfigPath." "ERROR"
  exit 1
}
if (-not $config.WarnMinutesBefore) { $config.WarnMinutesBefore = @(15,5,1) }
if (-not $config.FinalWarningSeconds) { $config.FinalWarningSeconds = 30 }
if (-not $config.LogoffGraceSeconds) { $config.LogoffGraceSeconds = 30 }

# Safety: warn if target user is an Administrator
if (Is-UserInAdministrators -UserName $config.TargetUsername) {
  Write-Log "WARNING: Target user '$($config.TargetUsername)' is in Administrators group. Consider making it a Standard user." "WARN"
}

# Load or init state
$state = Load-JsonFile -Path $StatePath -Default ([pscustomobject]@{
  CurrentWindowEnd = $null
  WarningsSent = @()
})

# Time now
if ($OverrideNow) {
  try { $now = [DateTime]::Parse($OverrideNow) } catch { $now = Get-Date }
} else {
  $now = Get-Date
}

# Single instance lock
$mutex = Get-Mutex -Name "XanBanMutex"
$hasHandle = $false
try {
  $hasHandle = $mutex.WaitOne([TimeSpan]::FromSeconds(5))
  if (-not $hasHandle) {
    Write-Log "Another instance is running. Exiting." "WARN"
    exit 0
  }

  # Determine window status
  $result = Get-AllowedWindowsForNow -Now $now -AllowedWindows $config.AllowedWindows
  $inside = [bool]$result.InsideWindow
  $current = $result.CurrentWindow
  $nextStart = $result.NextStart

  $target = "$($config.TargetUsername)"

  if ($inside -and $current) {
    # Inside allowed window: ensure user enabled
    Ensure-UserEnabled -UserName $target

    $end = [DateTime]$current.End
    $timeLeft = $end - $now
    $endKey = $end.ToString("o")

    # Reset warnings if window end changed
    if ($state.CurrentWindowEnd -ne $endKey) {
      $state.CurrentWindowEnd = $endKey
      $state.WarningsSent = @()
      Write-Log "Entered allowed window. Current window ends at $endKey."
    }

    # Send warnings at configured minutes before end (only once per threshold)
    $thresholds = @($config.WarnMinutesBefore | ForEach-Object {[int]$_} | Sort-Object -Descending)
    $sessions = @()
    if ($thresholds.Count -gt 0 -or $config.FinalWarningSeconds -gt 0) {
      $sessions = Get-UserSessionIds -UserName $target
    }

    foreach ($t in $thresholds) {
      $already = $state.WarningsSent -contains "$t"
      if (-not $already -and $timeLeft.TotalSeconds -le ($t * 60) -and $timeLeft.TotalSeconds -gt 0) {
        $msg = "Heads up: Your time ends in approximately $t minute(s). Please save your work."
        Send-WarningMessage -SessionIds $sessions -Message $msg
        Write-Log "Sent $t-minute warning to '$target'."
        $state.WarningsSent += "$t"
      }
    }

    # Final warning seconds
    $finalSent = $state.WarningsSent -contains "final"
    if (-not $finalSent -and $config.FinalWarningSeconds -gt 0 -and $timeLeft.TotalSeconds -le $config.FinalWarningSeconds -and $timeLeft.TotalSeconds -gt 0) {
      $msg = "Final warning: Logging off in $([int][Math]::Ceiling($timeLeft.TotalSeconds)) second(s)."
      Send-WarningMessage -SessionIds $sessions -Message $msg
      Write-Log "Sent final seconds warning to '$target'."
      $state.WarningsSent += "final"
    }

    # If past end, enforce logoff and disable
    if ($now -ge $end) {
      $sessions = Get-UserSessionIds -UserName $target
      if ($sessions.Count -gt 0) {
        $msg = "Time is up. You are being logged off now."
        Send-WarningMessage -SessionIds $sessions -Message $msg
        Start-Sleep -Seconds ([Math]::Min([int]$config.LogoffGraceSeconds, 60))
        Logoff-UserSessions -SessionIds $sessions
      }
      Ensure-UserDisabled -UserName $target
      Write-Log "Curfew enforced at end boundary. User '$target' disabled."
    }

  } else {
    # Outside allowed window: ensure user disabled
    Ensure-UserDisabled -UserName $target

    # Clear state as we're not in an active window
    if ($state.CurrentWindowEnd) {
      Write-Log "Exited allowed window."
    }
    $state.CurrentWindowEnd = $null
    $state.WarningsSent = @()

    if ($nextStart) {
      Write-Log "Next allowed start at $($nextStart.ToString("o"))."
    }
  }

  # Save state
  $state | Save-JsonFile -Path $StatePath

} finally {
  if ($hasHandle) { $mutex.ReleaseMutex() | Out-Null }
  $mutex.Dispose()
}