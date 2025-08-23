#!/bin/zsh
# ------------------------------------------------------------------
# SECURITY REVIEW (public repo readiness):
# - No credentials, API keys, tokens, or personal identifiers remain.
# - Remote names must be provided explicitly (placeholders blocked).
# - Input (REMOTE_1 / REMOTE_2) constrained to safe charset: [A-Za-z0-9_-].
# - Paths are fixed to /Volumes/Archives-{A,B}; no user-controlled path joins.
# - Version pruning restricted to one level under "$dest/_versions".
# - Logs may include filenames from your drives: DO NOT publish log contents.
# Recommendation: ensure .gitignore excludes _logs/ and any rclone config.
# If you intentionally want to allow placeholder remotes during testing,
# you can export ALLOW_DEFAULT_REMOTES=1 before running.
# ------------------------------------------------------------------
set -euo pipefail
umask 077   # secure default perms for created files/dirs

# Trap-based FD restore (covers early exits)
restore_fds_done=0
cleanup() {
  if [[ $restore_fds_done -eq 0 ]]; then
    exec 1>&3 2>&4 3>&- 4>&-
    restore_fds_done=1
  fi
}
trap cleanup EXIT

### ---- SETTINGS ----
CHECKERS=8
TRANSFERS=8
TPSLIMIT=10
RETENTION_DAYS=90          # days to keep snapshot folders in _versions
MODE="${MODE:-prod}"       # set MODE=test for a small capped run
MIN_FREE_SPACE_GB=50       # minimum free space required on destination

# Configure your remotes here - these should match your rclone config names
REMOTE_1="${REMOTE_1:-remote1}"  # Replace with your first rclone remote name
REMOTE_2="${REMOTE_2:-remote2}"  # Replace with your second rclone remote name

### ---- Validation ----
if ! command -v rclone &> /dev/null; then
  echo "ERROR: rclone not found. Please install rclone." >&2
  exit 1
fi

if [[ "$MODE" != "prod" && "$MODE" != "test" ]]; then
  echo "ERROR: MODE must be 'prod' or 'test', got: $MODE" >&2
  exit 1
fi

# Validate remote names (basic security check)
if [[ ! "$REMOTE_1" =~ ^[a-zA-Z0-9_-]+$ ]] || [[ ! "$REMOTE_2" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: Remote names must contain only alphanumeric characters, hyphens, and underscores" >&2
  exit 1
fi

# Ensure remotes are not using default placeholder values (unless override granted)
if [[ "${ALLOW_DEFAULT_REMOTES:-0}" != "1" && ( "$REMOTE_1" == "remote1" || "$REMOTE_2" == "remote2" ) ]]; then
  echo ""
  echo "❌ ERROR: Please configure your actual rclone remote names" >&2
  echo "Set environment variables: REMOTE_1=your_first_remote REMOTE_2=your_second_remote" >&2
  echo "Or export ALLOW_DEFAULT_REMOTES=1 to bypass (testing only)" >&2
  echo ""
  exit 1
fi

### ---- Pick Archives volume (A then B, if you add B later) ----
dest=""
echo ""
echo "=== CHECKING FOR ARCHIVES VOLUMES ==="
for vol in "/Volumes/Archives-A" "/Volumes/Archives-B"; do
  if [[ -d "$vol" ]]; then
    echo "✓ Found volume: $vol"
    # Check if writable
    if [[ -w "$vol" ]]; then
      dest="$vol"
      echo "✓ Selected destination: $dest"
      break
    else
      echo "⚠️  WARNING: $vol is not writable, skipping"
    fi
  else
    echo "✗ Volume not found: $vol"
  fi
done

if [[ -z "$dest" ]]; then
  echo ""
  echo "❌ ERROR: No writable Archives volume mounted." >&2
  echo "Please mount Archives-A or Archives-B and ensure it's writable." >&2
  exit 1
fi

### ---- Check available disk space ----
echo ""
echo "=== CHECKING DISK SPACE ==="
echo "Checking available disk space on $dest..."

# Use df -h and parse the human-readable output
available_space=$(df -h "$dest" | awk 'NR==2 {print $4}')
echo "Available space: ${available_space}"

# Convert to GB for comparison
case "$available_space" in
  *Ti) available_gb=$(echo "$available_space" | sed 's/Ti//' | awk '{printf "%.0f", $1 * 1024}') ;;
  *Gi) available_gb=$(echo "$available_space" | sed 's/Gi//' | awk '{printf "%.0f", $1}') ;;
  *Mi) available_gb=$(echo "$available_space" | sed 's/Mi//' | awk '{printf "%.0f", $1 / 1024}') ;;
  *G)  available_gb=$(echo "$available_space" | sed 's/G//' | awk '{printf "%.0f", $1}') ;;
  *M)  available_gb=$(echo "$available_space" | sed 's/M//' | awk '{printf "%.0f", $1 / 1024}') ;;
  *K)  available_gb=$(echo "$available_space" | sed 's/K//' | awk '{printf "%.0f", $1 / 1024 / 1024}') ;;
  *)   available_gb=0 ;;  # Unknown format, skip check
esac

echo "✓ Available space: ${available_gb}GB (converted from ${available_space})"

# Check if we have enough space
if [[ $available_gb -gt 0 && $available_gb -lt $MIN_FREE_SPACE_GB ]]; then
  echo ""
  echo "❌ ERROR: Insufficient disk space. Available: ${available_gb}GB, Required: ${MIN_FREE_SPACE_GB}GB" >&2
  exit 1
fi

echo ""
echo "=== INITIALIZING BACKUP ==="
ts=$(date +%F-%H%M%S)
logdir="$dest/_logs/$ts"
main_log="$logdir/main.log"

### ---- Create directories with error handling ----
for dir in "$logdir" "$dest/_versions" "$dest/$REMOTE_1" "$dest/$REMOTE_2"; do
  if ! mkdir -p "$dir"; then
    echo "ERROR: Failed to create directory: $dir" >&2
    exit 1
  fi
done

### ---- Initialize main log ----
# Save original file descriptors (trap will restore)
exec 3>&1 4>&2
exec 1> >(tee -a "$main_log")
exec 2> >(tee -a "$main_log" >&2)

echo ""
echo "================================================="
echo "=== Backup started at $(date) ==="
echo "================================================="
echo "📁 Backup dest: $dest"
echo "🔧 Mode: $MODE"
echo "💾 Available space: ${available_gb}GB"
echo "🔗 Including files shared with you: YES"
echo ""

### ---- rclone options ----
# Export Google Docs/Sheets/Slides to *Office* (docs->docx, sheets->xlsx, slides->pptx; drawings->svg).
# Other file types copy as-is.
rclone_main_common=(
  --fast-list --checkers $CHECKERS --transfers $TRANSFERS --tpslimit $TPSLIMIT --log-level INFO
  --drive-export-formats docx,xlsx,pptx,svg
)

echo "🔄 Will backup: Both your files AND files shared with you"
echo ""

### ---- Mirror "My Drive" for a given remote into dest_sub ----
mirror_my_drive() {
  local remote="$1" dest_sub="$2"
  local target="$dest/$dest_sub"
  local log_file="$logdir/${dest_sub//\//-}.log"
  local my_drive_errors=0
  local shared_errors=0
  
  echo "== MY DRIVE: $remote -> $target =="
  echo "Log file: $log_file"
  
  # Verify remote exists
  if ! rclone lsd "$remote:" --max-depth 1 &>/dev/null; then
    echo "ERROR: Cannot access remote '$remote'. Please check rclone config." >&2
    return 1
  fi
  
  # First backup regular "My Drive" files
  echo "🔄 Backing up your own files from My Drive..."
  local rclone_cmd=(
    rclone "${cmd[@]}" "$remote:/" "$target"
    "${rclone_main_common[@]}" "${limiter[@]}"
    --log-file "$log_file"
    --stats-one-line --stats 30s
  )
  
  if [[ "$MODE" == "prod" ]]; then
    rclone_cmd+=(--backup-dir "$dest/_versions/${dest_sub//\//-}-$ts")
  fi
  
  echo "Running: ${rclone_cmd[*]}"
  
  if ! "${rclone_cmd[@]}"; then
    my_drive_errors=1
    echo "✗ ERROR: Backing up My Drive failed" >&2
    echo "Continuing with shared files backup..." >&2
  else
    echo "✓ My Drive backup completed successfully"
  fi
  
  # Always try to backup shared files, even if My Drive failed
  echo "🔄 Backing up files shared with you to Shared_with_me subfolder..."
  local shared_target="$target/Shared_with_me"
  mkdir -p "$shared_target"
  
  local shared_cmd=(
    rclone "${cmd[@]}" "$remote:/" "$shared_target"
    "${rclone_main_common[@]}" "${limiter[@]}"
    --drive-shared-with-me
    --log-file "$log_file"
    --stats-one-line --stats 30s
  )
  
  echo "Running (shared files): ${shared_cmd[*]}"
  
  if ! "${shared_cmd[@]}"; then
    shared_errors=1
    echo "✗ ERROR: Backing up shared files failed" >&2
  else
    echo "✓ Shared files backup completed successfully"
  fi
  
  # Return appropriate exit code
  local total_errors=$((my_drive_errors + shared_errors))
  if [[ $total_errors -gt 0 ]]; then
    echo "✗ Backup for $remote completed with $total_errors error(s)" >&2
    echo "Check log: $log_file" >&2
    return $total_errors
  else
    echo "✓ Successfully completed backup for $remote (both own and shared files)"
    return 0
  fi
}

### ---- Test mode: tiny capped COPY; Prod: full SYNC with snapshotting of deletes/overwrites. ----
if [[ "$MODE" == "test" ]]; then
  limiter=( --max-transfer 200M --max-size 50M )
  cmd=( copy )
else
  limiter=()
  cmd=( sync )
fi

### ---- Run both Google Drives ----
backup_errors=0

echo ""
echo "=== STARTING GOOGLE DRIVE BACKUPS ==="
echo ""
echo "📂 Starting backup of $REMOTE_1..."
if ! mirror_my_drive "$REMOTE_1" "$REMOTE_1"; then
  backup_errors=$((backup_errors + $?))
  echo ""
  echo "⚠️  First backup had errors, continuing with second backup..."
  echo ""
fi

echo ""
echo "📂 Starting backup of $REMOTE_2..."
if ! mirror_my_drive "$REMOTE_2" "$REMOTE_2"; then
  backup_errors=$((backup_errors + $?))
fi

### ---- Retention: prune old snapshots ----
echo ""
echo "=== CLEANUP PHASE ==="
echo "🧹 Removing snapshots older than $RETENTION_DAYS days..."
if [[ -d "$dest/_versions" ]]; then
  # Symlink safety check
  if [[ -L "$dest/_versions" ]]; then
    echo "❌ SECURITY: '$dest/_versions' is a symlink. Aborting cleanup." >&2
    echo "Remove or replace the symlink with a real directory before continuing." >&2
    backup_errors=$((backup_errors + 1))
  else
    old_snapshots=$(find "$dest/_versions" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS 2>/dev/null || true)
    if [[ -n "$old_snapshots" ]]; then
      echo "Found old snapshots to remove:"
      echo "$old_snapshots"
      if find "$dest/_versions" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null; then
        echo "✓ Old snapshots removed successfully"
      else
        echo "✗ WARNING: Some old snapshots could not be removed" >&2
      fi
    else
      echo "✓ No old snapshots found to remove"
    fi
  fi
else
  echo "✓ No _versions directory found"
fi

### ---- Final status ----
echo ""
echo "================================================="
echo "=== Backup completed at $(date) ==="
echo "================================================="
echo "📅 Timestamp: $ts"
echo "📋 Logs directory: $logdir"
echo "📝 Main log: $main_log"
echo ""

if [[ $backup_errors -gt 0 ]]; then
  echo "❌ Backup completed with $backup_errors error(s)"
  echo "📋 Please review the logs for details:"
  echo "   - Check: $logdir/${REMOTE_1}.log"
  echo "   - Check: $logdir/${REMOTE_2}.log"
  echo ""
  echo "💡 Common issues:"
  echo "   - Check rclone config: rclone config show"
  echo "   - Verify Google Drive access permissions"
  echo "   - Check network connectivity"
  echo "   - Review individual log files for specific errors"
  echo ""
  
  cleanup
  exit 1
else
  echo "✅ All backups completed successfully!"
  echo "💿 You may eject the Archives volume."
  echo ""
  
  cleanup
  exit 0
fi