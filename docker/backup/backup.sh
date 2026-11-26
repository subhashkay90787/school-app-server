#!/bin/sh
# Nightly pg_dump at BACKUP_AT (local time); keeps BACKUP_DAILY_KEEP daily dumps and BACKUP_WEEKLY_KEEP weekly
# (Sunday) dumps under /backups. Restore: pg_restore -d school_app_db --clean /backups/daily/<file>.dump
set -eu
: "${BACKUP_AT:=02:30}" "${BACKUP_DAILY_KEEP:=14}" "${BACKUP_WEEKLY_KEEP:=8}"
mkdir -p /backups/daily /backups/weekly
while true; do
    now=$(date +%s); target=$(date -d "$(date +%F) $BACKUP_AT" +%s)
    [ "$target" -le "$now" ] && target=$((target + 86400))
    sleep $((target - now))
    stamp=$(date +%F_%H%M)
    file=/backups/daily/school_app_db_$stamp.dump
    if pg_dump -Fc -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$file.part"; then
        mv "$file.part" "$file"
        [ "$(date +%u)" = "7" ] && cp "$file" /backups/weekly/
        ls -1t /backups/daily/*.dump | tail -n +$((BACKUP_DAILY_KEEP + 1)) | xargs -r rm -f
        ls -1t /backups/weekly/*.dump 2>/dev/null | tail -n +$((BACKUP_WEEKLY_KEEP + 1)) | xargs -r rm -f
        echo "backup ok: $file"
    else
        rm -f "$file.part"; echo "backup FAILED at $stamp" >&2
    fi
done
