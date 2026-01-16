## Backup Scripts Debug Log

Date: 2026-01-16 16:07:41 +08

### Context
- User reports backups stopped after reboot; last run mid-December.
- Target folder: `/Users/zhl/Documents/02_Area_Code/Backup_scripts`

### Findings
- LaunchAgents were symlinks into Documents:
  - `/Users/zhl/Library/LaunchAgents/com.user.googledrive.backup.plist`
  - `/Users/zhl/Library/LaunchAgents/com.user.googledrive.backup.monitor.plist`
- `launchctl list` showed no loaded jobs for googledrive/backup.
- Monitor stderr log shows repeated failures:
  - `/Users/zhl/Library/Logs/com.user.googledrive.backup.monitor.stderr.log`
  - Error: `can't open input file: /Users/zhl/Documents/02_Area_Code/Backup_scripts/monitor_backup.sh`

### Actions Taken
- Read the scripts and plists:
  - `/Users/zhl/Documents/02_Area_Code/Backup_scripts/run_gdrives_backup.sh`
  - `/Users/zhl/Documents/02_Area_Code/Backup_scripts/monitor_backup.sh`
  - `/Users/zhl/Documents/02_Area_Code/Backup_scripts/com.user.googledrive.backup.plist`
  - `/Users/zhl/Documents/02_Area_Code/Backup_scripts/com.user.googledrive.backup.monitor.plist`
- Replaced LaunchAgent symlinks with real files:
  - Copied both plists into `/Users/zhl/Library/LaunchAgents/`
  - Removed the symlinks in that directory
- Attempted `launchctl bootstrap` (sandboxed) -> failed with:
  - `Bootstrap failed: 5: Input/output error`

### Current State
- LaunchAgents exist as regular files in `/Users/zhl/Library/LaunchAgents/`.
- Jobs are still not loaded.
- Sandbox restrictions prevented running `launchctl` unsandboxed for richer errors.

### Next Steps (run in Terminal)
```bash
launchctl bootout gui/$(id -u)/com.user.googledrive.backup 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.user.googledrive.backup.monitor 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.monitor.plist
launchctl list | grep -E "googledrive|backup"
```

Optional diagnostics if it still fails:
```bash
launchctl print gui/$(id -u)/com.user.googledrive.backup | head -40
launchctl print gui/$(id -u)/com.user.googledrive.backup.monitor | head -40
```

### Hypothesis to Confirm
- If `~/Documents` is iCloud-managed, `Backup_scripts` may be offloaded at login.
- Ensure `Backup_scripts` is set to "Keep Downloaded" in Finder.
