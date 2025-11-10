# xanban - Session Context

**Last Updated**: 2025-11-09 17:38
**Status**: Production
**Version**: v1.0.0
**Brand**: LaClair Technologies

## Quick Status

- **Current Phase**: Production / Parental Controls
- **Active Work**: Monitoring and maintenance
- **Blockers**: None
- **Next Steps**: Update as needed for Xander's usage patterns

## Project Overview

### Purpose

Windows time-based local account enforcement system for parental controls - automatically enables/disables Xander's Windows account based on daily usage windows with warnings before curfew.

### Technology Stack

- **Language**: PowerShell
- **Scheduler**: Windows Task Scheduler
- **Permissions**: Runs as SYSTEM
- **Configuration**: JSON config file
- **Target**: Windows local accounts (cmdlets)

### Repository Info

- **GitHub**: https://github.com/plac9/xanban
- **Brand**: LaClair Technologies
- **Target**: Xander's Windows account

## Current State

### What's Working

✅ Daily usage window enforcement
✅ Configurable start/end times
✅ Warning notifications (15min, 5min, 1min before curfew)
✅ Automatic account disable/enable
✅ User logoff at curfew
✅ Self-healing at startup (if PC was off during scheduled changes)
✅ Runs as SYSTEM via scheduled task

### Configuration

**Location**: `C:\ProgramData\XanBan\config.json`

**Example**:
```json
{
  "allowedHours": {
    "start": "07:00",
    "end": "21:00"
  },
  "targetUser": "Xander",
  "warnings": {
    "15min": true,
    "5min": true,
    "1min": true
  }
}
```

### Features

1. **Daily Usage Windows**: Configurable start/end times
2. **Warning Notifications**: 15min, 5min, 1min before curfew
3. **Automatic Disable**: Account disabled at curfew time
4. **Automatic Enable**: Account re-enabled at start time
5. **User Logoff**: Forces logoff at curfew
6. **Self-Healing**: Catches up on missed changes if PC was off
7. **System Service**: Runs as SYSTEM for reliability

## Development Workflow

### Installation

```powershell
# Copy XanBan scripts to appropriate location
# Create scheduled task (as SYSTEM)
# Configure C:\ProgramData\XanBan\config.json
```

### Common Tasks

```powershell
# Update allowed hours
# Edit C:\ProgramData\XanBan\config.json

# Test enforcement
# Check Windows Task Scheduler
# View task history
```

## Use Case

**Target**: Xander's Windows account
**Allowed Hours**: Typically 07:00-21:00 (7am to 9pm)
**Purpose**: Enforce healthy screen time limits
**Warnings**: Give advance notice before account locks

## Deployment

- **Platform**: Windows (local account management)
- **Permissions**: SYSTEM (via Task Scheduler)
- **Config**: JSON file in ProgramData

## Resources

- Part of LaClair Technologies portfolio
- Windows local account cmdlets
- Task Scheduler documentation

---

**Note**: Adjust allowed hours in config.json as needed for Xander's schedule.
