#!/bin/bash

# ==============================================================================
# Script: Install Rootless Docker + Compose on Debian 13 (Trixie) - FIXED
# ==============================================================================

# Bei Fehlern abbrechen
set -e

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}### Start: Rootless Docker Setup für Debian 13 (Fix Version) ###${NC}"

if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}Fehler: Bitte als normaler User starten (nicht root).${NC}"
    exit 1
fi

USER_ID=$(id -u)
USERNAME=$(whoami)

# ------------------------------------------------------------------------------
# 1. System & Dependencies
# ------------------------------------------------------------------------------
echo -e "${BLUE}--> [1/5] Systemkonfiguration (sudo)...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq uidmap dbus-user-session fuse-overlayfs curl iptables slirp4netns

# Kernel Module Fix
if ! lsmod | grep -q nf_tables; then
    echo "Lade nf_tables..."
    sudo modprobe nf_tables
fi
echo "nf_tables" | sudo tee /etc/modules-load.d/rootless-docker.conf > /dev/null

# Sysctl Fixes
sudo sh -c 'echo "net.ipv4.ip_unprivileged_port_start=80" > /etc/sysctl.d/50-unprivileged-ports.conf'
sudo sh -c 'echo "net.ipv4.ping_group_range = 0 2147483647" > /etc/sysctl.d/50-docker-ping.conf'
sudo sysctl --system > /dev/null

# ------------------------------------------------------------------------------
# 2. Docker Rootless Install
# ------------------------------------------------------------------------------
echo -e "${BLUE}--> [2/5] Docker Rootless Installation...${NC}"
# Nur installieren, wenn noch nicht da (spart Zeit beim Rerun)
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com/rootless | sh
else
    echo "Docker scheint bereits installiert zu sein. Fahre fort..."
fi

# ------------------------------------------------------------------------------
# 3. Docker Compose Plugin
# ------------------------------------------------------------------------------
echo -e "${BLUE}--> [3/5] Docker Compose Plugin...${NC}"
mkdir -p ~/.docker/cli-plugins
COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)"

if [ ! -f ~/.docker/cli-plugins/docker-compose ]; then
    curl -L $COMPOSE_URL -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
else
    echo "Docker Compose bereits vorhanden."
fi

# ------------------------------------------------------------------------------
# 4. .bashrc Config (HIER WAR DER FEHLER)
# ------------------------------------------------------------------------------
echo -e "${BLUE}--> [4/5] Aktualisiere .bashrc...${NC}"

BASHRC_FILE="$HOME/.bashrc"

# Header
if ! grep -q "# --- Docker Rootless Config ---" "$BASHRC_FILE"; then
    echo "" >> "$BASHRC_FILE"
    echo "# --- Docker Rootless Config ---" >> "$BASHRC_FILE"
fi

# Sichere Funktion zum Hinzufügen (verhindert Crash bei set -e)
safe_append() {
    local LINE="$1"
    # grep gibt 1 zurück wenn nicht gefunden, das ! dreht es um,
    # sodass der if-Block betreten wird. Das löst keinen set -e Abbruch aus.
    if ! grep -qF "$LINE" "$BASHRC_FILE"; then
        echo "$LINE" >> "$BASHRC_FILE"
        echo "Hinzugefügt: $LINE"
    else
        echo "Bereits vorhanden: $LINE"
    fi
}

safe_append "export PATH=/home/$USERNAME/bin:\$PATH"
safe_append "export DOCKER_HOST=unix:///run/user/$USER_ID/docker.sock"
safe_append "alias docker-compose='docker compose'"

echo "Variablen erfolgreich geprüft/gesetzt."

# ------------------------------------------------------------------------------
# 5. Services Starten
# ------------------------------------------------------------------------------
echo -e "${BLUE}--> [5/5] Starte Dienste...${NC}"

systemctl --user enable docker
systemctl --user start docker

if [ "$(loginctl show-user $USERNAME -p Linger | cut -d= -f2)" != "yes" ]; then
    echo "Aktiviere Linger..."
    sudo loginctl enable-linger $USERNAME
fi

echo -e "${GREEN}### Installation fertig! ###${NC}"
echo -e "Bitte ausführen: ${GREEN}source ~/.bashrc${NC}"
