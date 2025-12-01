# Google Drive Backup Script

Automated backup script for multiple Google Drive accounts to external storage volumes, with optional macOS automation.

## ⚠️ Security Notice

**Before using this script:**
1. Configure your actual rclone remote names
2. Never commit personal remote names or credentials
3. Review logs before sharing (may contain file paths)

## Setup

### 1. Install rclone
```bash
brew install rclone
# or download from https://rclone.org
```

### 2. Configure your Google Drive remotes
```bash
rclone config
```
Follow the prompts to set up your Google Drive remotes. Choose meaningful names like:
- `work_drive`
- `personal_drive`
- `backup_account`

### 3. Configure the script
Edit the script to set your remote names, or use environment variables:

```bash
# Option A: Edit the script defaults
REMOTE_1="${REMOTE_1:-work_drive}"
REMOTE_2="${REMOTE_2:-personal_drive}"

# Option B: Use environment variables (recommended)
export REMOTE_1="work_drive"
export REMOTE_2="personal_drive"
```

## Features

- ✅ Backs up multiple Google Drive accounts
- ✅ Backs up both your own files AND files shared with you
- ✅ Organizes shared files in dedicated "Shared_with_me" subfolders
- ✅ Automatic external volume detection (Archives-A/Archives-B)
- ✅ Disk space validation
- ✅ Export Google Docs/Sheets/Slides to Office formats
- ✅ Comprehensive logging and error reporting
- ✅ Snapshot versioning with automatic cleanup
- ✅ Test mode for safe initial runs
- ✅ Continues backup even if one drive fails
- ✅ Automated backup monitoring with macOS notifications

## Backup Structure

The script creates this folder structure on your external drive:
```
/Volumes/Archives-A/
├── work_drive/
│   ├── (your personal files and folders)
│   └── Shared_with_me/
│       └── (files shared with you)
├── personal_drive/
│   ├── (your personal files and folders)
│   └── Shared_with_me/
│       └── (files shared with you)
└── _logs/
    └── (backup logs organized by timestamp)
```

## Usage

### Test Mode (Recommended first)
```bash
REMOTE_1="work_drive" REMOTE_2="personal_drive" MODE=test ./run_gdrives_backup.sh
```

### Production Mode
```bash
REMOTE_1="work_drive" REMOTE_2="personal_drive" ./run_gdrives_backup.sh
```

## Automation Setup (Optional)

For automated daily backups, you can set up a macOS LaunchAgent:

### 1. Create Automator Application
1. Open Automator and create a new Application
2. Add "Run Shell Script" action
3. Set the script to run your backup command
4. Save as `RunGDrivesBackup.app` in `/Applications/`

### 2. Install LaunchAgent
```bash
# Copy the example plist and customize it
cp com.user.googledrive.backup.plist.example com.user.googledrive.backup.plist

# Edit the plist file to match your setup
# - Update remote names
# - Verify paths are correct
# - IMPORTANT: Set RunAtLoad to true for auto-start on boot

# Create symlink in LaunchAgents directory
ln -sf $(pwd)/com.user.googledrive.backup.plist ~/Library/LaunchAgents/

# Load it (will run immediately and then daily at 23:00)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.plist
```

**Important Configuration:**
- Set `<key>RunAtLoad</key><true/>` in the plist to ensure the backup service automatically starts after system reboots
- Without this setting, backups will stop running after a reboot until manually reloaded

### 3. Managing the LaunchAgent
```bash
# Check status
launchctl list | grep googledrive

# Stop the service
launchctl bootout gui/$(id -u)/com.user.googledrive.backup

# Restart after system reboot or if service stops (should happen automatically, but if needed):
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.plist

# View logs
tail -f ~/Library/Logs/com.user.googledrive.backup.stdout.log
```

## Backup Monitoring (Optional)

The `monitor_backup.sh` script checks if backups are running successfully and sends macOS notifications.

### Setup Monitoring

```bash
# Make the script executable
chmod +x monitor_backup.sh

# Test it manually
./monitor_backup.sh check    # Check status and send notification
./monitor_backup.sh summary  # Display backup summary report

# Install automated monitoring (runs daily at 9 AM)
# NOTE: Ensure RunAtLoad is set to true in the plist for auto-start on boot
ln -sf $(pwd)/com.user.googledrive.backup.monitor.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.googledrive.backup.monitor.plist
```

### Monitoring Features

The monitoring script will send macOS notifications for:
- ✅ **Success**: Backup completed successfully
- ❌ **Failure**: Backup encountered errors
- ⚠️ **Warning**: Backup hasn't run in 26+ hours
- ⏳ **Running**: Backup is currently in progress

### Monitoring Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `MAX_AGE_HOURS` | 26 | Alert if last backup is older than this |

### Monitoring Logs

Monitor logs are saved to:
- `~/Library/Logs/backup_monitor.log` - Monitoring activity log
- `~/Library/Logs/backup_last_status.txt` - Latest backup status
- `~/Library/Logs/com.user.googledrive.backup.monitor.stdout.log` - LaunchAgent stdout
- `~/Library/Logs/com.user.googledrive.backup.monitor.stderr.log` - LaunchAgent stderr

## Error Handling

The script is designed to be resilient:
- If backing up your personal files fails, it will still attempt to backup shared files
- If one Google Drive account fails, it will continue with the next one
- All errors are logged and reported at the end
- The script provides clear exit codes for automation

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `CHECKERS` | 8 | Number of parallel file checks |
| `TRANSFERS` | 8 | Number of parallel transfers |
| `RETENTION_DAYS` | 90 | Days to keep old snapshots |
| `MIN_FREE_SPACE_GB` | 50 | Minimum required free space |

## Security Best Practices

- 🔒 Never commit rclone config files
- 🔒 Use environment variables for sensitive configuration
- 🔒 The LaunchAgent plist contains personal remote names - don't commit it
- 🔒 Regularly review and rotate access tokens
- 🔒 Review log files before sharing
- 🔒 Use specific, non-personal remote names in public examples

## Troubleshooting

1. **"Cannot access remote" error**: Check `rclone config show`
2. **Permission errors**: Verify Google Drive API access
3. **Network timeouts**: Check internet connection
4. **Disk space errors**: Free up space on destination volume

## Log Files

Logs are saved to `<destination>/_logs/<timestamp>/`:
- `main.log` - Combined output from entire backup session
- `<remote1>.log` - First remote backup log (both personal and shared files)
- `<remote2>.log` - Second remote backup log (both personal and shared files)
