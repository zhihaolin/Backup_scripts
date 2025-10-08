#!/bin/zsh
# ------------------------------------------------------------------
# Backup Monitoring Script
#
# This script checks if the backup job ran successfully and sends
# notifications if it fails or doesn't run at all.
# ------------------------------------------------------------------
set -euo pipefail

# Configuration
BACKUP_LOG_DIR="$HOME/Library/Logs/Backups"
MONITOR_LOG="$HOME/Library/Logs/backup_monitor.log"
LAUNCHD_LOG_STDOUT="$HOME/Library/Logs/com.user.googledrive.backup.stdout.log"
LAUNCHD_LOG_STDERR="$HOME/Library/Logs/com.user.googledrive.backup.stderr.log"
STATUS_FILE="$HOME/Library/Logs/backup_last_status.txt"

# How many hours ago should we check for a successful backup?
# Default: 26 hours (allows for daily backups with some buffer)
MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MONITOR_LOG"
}

send_notification() {
  local title="$1"
  local message="$2"
  local sound="${3:-default}"

  # macOS native notification
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\""

  log "NOTIFICATION: $title - $message"
}

check_backup_status() {
  log "=== Starting backup monitoring check ==="

  # Check if backup log directory exists
  if [[ ! -d "$BACKUP_LOG_DIR" ]]; then
    log "ERROR: Backup log directory not found: $BACKUP_LOG_DIR"
    send_notification "⚠️ Backup Monitor" "Backup logs directory not found" "Basso"
    echo "FAILED: No log directory" > "$STATUS_FILE"
    return 1
  fi

  # Find the most recent automator log
  latest_log=$(ls -t "$BACKUP_LOG_DIR"/automator-*.log 2>/dev/null | head -1)

  if [[ -z "$latest_log" ]]; then
    log "WARNING: No backup logs found in $BACKUP_LOG_DIR"
    send_notification "⚠️ Backup Monitor" "No backup logs found - backup may not have run" "Basso"
    echo "FAILED: No logs found" > "$STATUS_FILE"
    return 1
  fi

  log "Latest backup log: $latest_log"

  # Check log age
  if [[ "$(uname)" == "Darwin" ]]; then
    log_age_seconds=$(( $(date +%s) - $(stat -f %m "$latest_log") ))
  else
    log_age_seconds=$(( $(date +%s) - $(stat -c %Y "$latest_log") ))
  fi

  log_age_hours=$(( log_age_seconds / 3600 ))
  log "Log age: ${log_age_hours} hours"

  if [[ $log_age_hours -gt $MAX_AGE_HOURS ]]; then
    log "WARNING: Latest backup log is ${log_age_hours} hours old (threshold: ${MAX_AGE_HOURS}h)"
    send_notification "⚠️ Backup Overdue" "Last backup was ${log_age_hours} hours ago" "Basso"
    echo "FAILED: Log too old (${log_age_hours}h)" > "$STATUS_FILE"
    return 1
  fi

  # Check for success/failure indicators in the log
  if grep -q "✅ All backups completed successfully!" "$latest_log"; then
    log "SUCCESS: Backup completed successfully"
    send_notification "✅ Backup Success" "All backups completed successfully" "Glass"
    echo "SUCCESS: $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
    return 0
  elif grep -q "❌ Backup completed with .* error(s)" "$latest_log"; then
    error_count=$(grep -o "Backup completed with [0-9]* error(s)" "$latest_log" | grep -o "[0-9]*" | head -1)
    log "FAILURE: Backup completed with ${error_count} error(s)"
    send_notification "❌ Backup Failed" "Backup had ${error_count} error(s). Check logs." "Basso"
    echo "FAILED: ${error_count} errors at $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"

    # Show excerpt from log
    log "Error excerpt from backup log:"
    tail -20 "$latest_log" | tee -a "$MONITOR_LOG"

    return 1
  elif grep -q "ERROR:" "$latest_log"; then
    log "FAILURE: Errors detected in backup log"
    send_notification "❌ Backup Error" "Errors detected in backup. Check logs." "Basso"
    echo "FAILED: Errors detected at $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"

    # Show errors from log
    log "Errors found in backup log:"
    grep "ERROR:" "$latest_log" | tail -10 | tee -a "$MONITOR_LOG"

    return 1
  else
    # Log exists but no clear success/failure marker - might still be running
    log "UNKNOWN: No clear success/failure indicator in log"

    # Check if backup process is currently running
    if ps aux | grep -q "[r]un_gdrives_backup.sh"; then
      log "INFO: Backup appears to be currently running"
      send_notification "⏳ Backup Running" "Backup is currently in progress" "default"
      echo "RUNNING: Started at $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
      return 0
    else
      log "WARNING: No clear status and backup not running"
      send_notification "⚠️ Backup Status Unknown" "Check backup logs for details" "Basso"
      echo "UNKNOWN: No clear status at $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
      return 1
    fi
  fi
}

# Generate daily summary report
generate_summary() {
  log "=== Generating backup summary ==="

  if [[ ! -f "$STATUS_FILE" ]]; then
    log "No status file found"
    return
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 BACKUP STATUS SUMMARY"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$STATUS_FILE"
  echo ""

  if [[ -d "$BACKUP_LOG_DIR" ]]; then
    echo "📁 Recent backup logs:"
    ls -lht "$BACKUP_LOG_DIR"/automator-*.log 2>/dev/null | head -5 || echo "  No logs found"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# Main execution
main() {
  local mode="${1:-check}"

  case "$mode" in
    check)
      check_backup_status
      ;;
    summary)
      generate_summary
      ;;
    *)
      echo "Usage: $0 {check|summary}"
      echo "  check   - Check backup status and send notification"
      echo "  summary - Display backup status summary"
      exit 1
      ;;
  esac
}

main "$@"
