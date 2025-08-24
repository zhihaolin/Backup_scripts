# Google Drive Backup Script

Automated backup script for multiple Google Drive accounts to external storage volumes.

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
- 🔒 Regularly review and rotate access tokens
- 🔒 Review log files before sharing
- 🔒 Use specific, non-personal remote names

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
