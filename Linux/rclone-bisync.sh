# --- Variablen ---
SMB_PATH="//x.x.x.x/truenas-sync"
MOUNT_POINT="/mnt/ext/truenas-sync"
CRED_FILE="/mnt/Pool/Admin/.smbcredentials"
LOCAL_DIR="/mnt/Pool/Dataset/Snapshot-Test"
LOG_FILE="/mnt/Pool/Admin/rclone_smb.log"
RCLONE_WORKDIR="/mnt/Pool/Admin/rclone_workdir"
LOCK_FILE="/tmp/rclone_smb_sync.lock"

# --- 1. Der Überschneidungs-Schutz (flock) ---
# Wir weisen dem Lockfile den Dateideskriptor 9 zu und prüfen, ob er frei ist
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): INFO - Ein vorheriger Cronjob läuft noch. Abbruch, um Überschneidung zu verhindern." >> "$LOG_FILE"
    exit 0
fi

# --- Skript Start ---
echo "=========================================" >> "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S'): Skript gestartet." >> "$LOG_FILE"

# Arbeitsverzeichnisse erstellen
mkdir -p "$MOUNT_POINT"
mkdir -p "$RCLONE_WORKDIR"

# Sicherheitsnetz: Wird bei JEDEM Beenden des Skripts ausgeführt
cleanup() {
    if mountpoint -q "$MOUNT_POINT"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Führe Unmount aus..." >> "$LOG_FILE"
        umount -l "$MOUNT_POINT"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): SMB erfolgreich getrennt." >> "$LOG_FILE"
    fi
}
trap cleanup EXIT

# SMB Share mounten
if mount -t cifs "$SMB_PATH" "$MOUNT_POINT" -o credentials="$CRED_FILE",uid=root,gid=root,vers=3.0,iocharset=utf8,noserverino,noperm; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): SMB gemountet. Starte rclone bisync..." >> "$LOG_FILE"

    # --- Rclone Bisync Befehl ---
    # ACHTUNG: Für den allerersten Lauf MUSS das Flag --resync hinzugefügt werden!
    # Danach (für den regulären Cronjob) das --resync Flag unbedingt entfernen.
    # --conflict-resolve newer = Behält bei Konflikten immer die zuletzt geänderte Datei
    rclone bisync "$LOCAL_DIR" "$MOUNT_POINT" \
        --workdir "$RCLONE_WORKDIR" \
        --conflict-resolve newer \
        --create-empty-src-dirs \
        --min-age 1m \
        --exclude ".*" \
        --exclude ".*/**" \
        --retries=10 --retries-sleep=60s --resilient \
        --transfers=16 \
        >> "$LOG_FILE" 2>&1

#        --check-access \
#        --verbose \

    RCLONE_STATUS=$?

    if [ $RCLONE_STATUS -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): rclone bisync ERFOLGREICH abgeschlossen." >> "$LOG_FILE"
        exit 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S'): FEHLER - rclone ist mit Exit-Code $RCLONE_STATUS fehlgeschlagen!" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S'): FEHLER - Mount von $SMB_PATH fehlgeschlagen. Abbruch." >> "$LOG_FILE"
    exit 1
fi
