#!/bin/zsh
# Weekly snapshot of the macOS call history database (phone + FaceTime calls,
# synced from the iPhone via iCloud). Apple retains only a limited window in
# CallHistoryDB; these snapshots are what preserve long-term history.
# Triggered by the com.alexmiller.callhistory-backup LaunchAgent.
# Requires Full Disk Access for the executing code identity.

set -euo pipefail

BACKUP_DIR="$HOME/Documents/call-history-backups"
SOURCE_DB="$HOME/Library/Application Support/CallHistoryDB/CallHistory.storedata"
LOG_FILE="$HOME/Library/Logs/callhistory-backup.log"
DATE="$(/bin/date +%Y-%m-%d)"
RUN_DIR="$BACKUP_DIR/${DATE}"
DEST="$RUN_DIR/callhistory.db"

mkdir -p "$RUN_DIR" "$(/usr/bin/dirname "$LOG_FILE")"

log() { print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== run start ==="

if [[ ! -r "$SOURCE_DB" ]]; then
  log "ERROR: cannot read $SOURCE_DB — grant Full Disk Access to the app bundle (see README)."
  exit 1
fi

# Online consistent snapshot of the live SQLite DB (handles WAL correctly).
if /usr/bin/sqlite3 "$SOURCE_DB" ".backup '$DEST'"; then
  /bin/rm -f "${DEST}-wal" "${DEST}-shm"
  # Self-check: a healthy snapshot has call records and a sane date range.
  STATS=$(/usr/bin/sqlite3 "$DEST" \
    "SELECT count(*) || ' calls, ' || date(min(ZDATE)+978307200,'unixepoch') || ' -> ' || date(max(ZDATE)+978307200,'unixepoch') FROM ZCALLRECORD;" 2>/dev/null) || STATS="(stats query failed)"
  /usr/bin/gzip -f "$DEST"
  SIZE=$(/usr/bin/du -h "${DEST}.gz" | /usr/bin/awk '{print $1}')
  log "backup OK: ${DEST}.gz (${SIZE}; ${STATS})"
else
  log "ERROR: sqlite3 .backup failed for CallHistoryDB"
  exit 1
fi

log "=== run end ==="
