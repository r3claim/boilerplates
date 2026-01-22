#!/bin/bash

# ============================
# Swap-Datei erstellen (Debian)
# ============================

# Größe der Swap-Datei hier anpassen (z.B. 2G, 512M, 4G)
SWAPSIZE="2G"
SWAPFILE="/swapfile"

# Prüfen, ob das Skript als Root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als Root ausführen (sudo)."
  exit 1
fi

echo "Erstelle Swap-Datei mit Größe: $SWAPSIZE ..."

# Swap-Datei erstellen
if command -v fallocate >/dev/null 2>&1; then
  fallocate -l $SWAPSIZE $SWAPFILE
else
  # fallback auf dd, falls fallocate nicht verfügbar ist
  SIZE_MB=$(echo $SWAPSIZE | grep -o -E '[0-9]+')
  dd if=/dev/zero of=$SWAPFILE bs=1M count=$SIZE_MB
fi

# Berechtigungen setzen
chmod 600 $SWAPFILE

# Swap formatieren
mkswap $SWAPFILE

# Swap aktivieren
swapon $SWAPFILE

# Eintrag in /etc/fstab prüfen und ggf. hinzufügen
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# Swappiness optional setzen (hier auf 10)
sysctl vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
  echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "Swap-Datei erfolgreich erstellt und aktiviert!"
swapon --show
free -h
