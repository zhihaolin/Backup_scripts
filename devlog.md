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

---

Date: 2026-01-16 16:57:57 +0800

### Context
- Updated README to align with the debug notes and recovery steps.
- Added example LaunchAgent plists and adjusted ignore rules so examples are tracked.

### Actions Taken
- Added `com.user.googledrive.backup.plist.example` and `com.user.googledrive.backup.monitor.plist.example`.
- Updated `.gitignore` to keep real `.plist` files ignored while allowing `*.plist.example`.
- Committed and pushed: `docs: add LaunchAgent plist examples`.

### Current State
- Repo clean and up to date on `origin/main`.
- Local `.plist` files remain gitignored and must be installed as real files under `~/Library/LaunchAgents/`.

### Next Steps (next session)
1. Create or update local plist files from the `.plist.example` templates and fix all paths.
2. Copy local plists into `~/Library/LaunchAgents/` (avoid symlinks if the repo is iCloud-managed).
3. Ensure `monitor_backup.sh` is executable and the script path in the monitor plist is correct.
4. Reload with `launchctl` and verify job status/logs:
```bash
launchctl bootout gui/$(id -u)/com.user.googledrive.backup 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.user.googledrive.backup.monitor 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.monitor.plist
launchctl list | grep -E "googledrive|backup"
```
5. If it still fails, run:
```bash
launchctl print gui/$(id -u)/com.user.googledrive.backup | head -40
launchctl print gui/$(id -u)/com.user.googledrive.backup.monitor | head -40
```
