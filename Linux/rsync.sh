#!/bin/bash

# --- Variablen ---
SMB_PATH="//x.x.x.x/truenas-sync"
MOUNT_POINT="/mnt/ext/truenas-sync"
CRED_FILE="/mnt/Pool/Admin/.smbcredentials"
SOURCE_DIR="/mnt/Pool/Dataset/Snapshot-Test"
LOG_FILE="/mnt/Pool/Admin/rsync_smb.log"

echo "=========================================" >> "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S'): Skript gestartet." >> "$LOG_FILE"

mkdir -p "$MOUNT_POINT"

# Sicherheitsnetz: Wird bei JEDEM Beenden des Skripts ausgeführt (egal ob Fehler oder Erfolg)
cleanup() {
    # Prüft, ob der Mountpoint aktuell noch gemountet ist
    if mountpoint -q "$MOUNT_POINT"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Führe Unmount aus..." >> "$LOG_FILE"
        # -l (lazy) sorgt dafür, dass der Mount auch dann getrennt wird, wenn er noch beschäftigt scheint
        umount -l "$MOUNT_POINT"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): SMB erfolgreich getrennt." >> "$LOG_FILE"
    fi
}
# Aktiviert das Sicherheitsnetz für alle Exit-Szenarien
trap cleanup EXIT

# SMB Share mounten
if mount -t cifs "$SMB_PATH" "$MOUNT_POINT" -o credentials="$CRED_FILE",uid=root,gid=root,vers=3.0; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): SMB gemountet. Starte rsync..." >> "$LOG_FILE"
    
    # rsync ausführen
    rsync -avh --delete "$SOURCE_DIR" "$MOUNT_POINT/" >> "$LOG_FILE" 2>&1
    RSYNC_STATUS=$?
    
    if [ $RSYNC_STATUS -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync ERFOLGREICH abgeschlossen." >> "$LOG_FILE"
        # Das Skript beendet sich hier normal. Der "trap" greift automatisch und macht den Unmount.
        exit 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S'): FEHLER - rsync ist mit Exit-Code $RSYNC_STATUS fehlgeschlagen!" >> "$LOG_FILE"
        # Beendet mit Fehlercode. Auch hier greift der "trap" und räumt den Mount auf.
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S'): FEHLER - Mount von $SMB_PATH fehlgeschlagen. Abbruch." >> "$LOG_FILE"
    exit 1
fi
