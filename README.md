# XanBan (Windows time-based local account enforcement)

XanBan enforces daily usage windows for a local Windows account:
- Warns at configurable times before curfew.
- Logs off the user at curfew and disables the account.
- Re-enables the account at the next allowed start time.
- Self-heals at startup if the PC was off during a scheduled enable/disable.
- Runs under SYSTEM via a scheduled task.

Only the specified account is affected. Local Administrator accounts are untouched.

## Install

1) Open an elevated PowerShell (Run as Administrator).
2) From the repo root, run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\Install-XanBan.ps1 -TargetUsername "ChildUser" -AllowedStart "07:00" -AllowedEnd "21:00" -WarnMinutesBefore 15,5,1
```

This will:
- Copy `XanBan.ps1` to `C:\ProgramData\XanBan`.
- Create `C:\ProgramData\XanBan\config.json`.
- Register a Scheduled Task "XanBan Enforcer" running as SYSTEM at startup and every minute.

Config lives at `C:\ProgramData\XanBan\config.json`.

## Configuration

Example:
```json
{
  "TargetUsername": "ChildUser",
  "AllowedWindows": [
    { "Start": "07:00", "End": "21:00" }
  ],
  "WarnMinutesBefore": [15, 5, 1],
  "FinalWarningSeconds": 30,
  "LogoffGraceSeconds": 30
}
```

- AllowedWindows supports multiple windows, including windows that wrap midnight (e.g., Start=22:00, End=06:30).
- Warnings are sent using the built-in "msg" command to the user's active sessions.

## How it works

- Inside the allowed window:
  - The user is enabled (if disabled).
  - The script sends warnings at the configured minute marks before the end.
- At the end boundary:
  - The user receives a final notification, is logged off, and the account is disabled.
- Outside the allowed window:
  - The account is kept disabled.
- At startup:
  - The script reconciles the account state based on the current time (failsafe).

## Testing

You can simulate "now" by running the script manually with `-OverrideNow`:
```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\XanBan\XanBan.ps1" -OverrideNow "2025-01-01T20:59:00"
```

## Uninstall

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\Uninstall-XanBan.ps1 -RemoveFiles
```

## Notes and recommendations

- Ensure the target account is a Standard (non-Administrator) user.
- This solution depends on Windows Task Scheduler and the built-in "msg", "logoff", and local accounts cmdlets.
- Logs: `C:\ProgramData\XanBan\XanBan.log`.
- State: `C:\ProgramData\XanBan\state.json`.
- For more complex rules (per-day schedules, total screen time caps), the config and script can be extended.
