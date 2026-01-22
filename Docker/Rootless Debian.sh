#!/usr/bin/env bash
set -e

echo "== Rootless Docker Setup für Debian 13 =="

# Prüfen, ob Docker vorhanden ist
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker ist nicht installiert."
  exit 1
fi

echo "✔ Docker gefunden: $(docker --version)"

# Benötigte Pakete installieren
echo "== Installiere benötigte Pakete =="
sudo apt update
sudo apt install -y \
  uidmap \
  dbus-user-session \
  slirp4netns \
  fuse-overlayfs

# Rootless Docker einrichten
echo "== Richte Rootless Docker ein =="
dockerd-rootless-setuptool.sh install

# DOCKER_HOST setzen
DOCKER_HOST_LINE='export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock'

if ! grep -q "DOCKER_HOST=unix:///run/user" ~/.bashrc; then
  echo "$DOCKER_HOST_LINE" >> ~/.bashrc
  echo "✔ DOCKER_HOST zu ~/.bashrc hinzugefügt"
else
  echo "✔ DOCKER_HOST bereits gesetzt"
fi

export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

# systemd User-Service aktivieren
echo "== Aktiviere Docker User-Service =="
systemctl --user enable docker
systemctl --user start docker

# Linger aktivieren
echo "== Aktiviere systemd linger für $USER =="
sudo loginctl enable-linger "$USER"

# Optional: unprivilegierte Ports erlauben
echo "== Erlaube Ports <1024 (optional, empfohlen) =="
SYSCTL_FILE="/etc/sysctl.d/99-rootless-docker.conf"
if [ ! -f "$SYSCTL_FILE" ]; then
  echo "net.ipv4.ip_unprivileged_port_start=0" | sudo tee "$SYSCTL_FILE"
  sudo sysctl --system
  echo "✔ Ports <1024 freigegeben"
else
  echo "✔ Port-Freigabe bereits konfiguriert"
fi

# Test
echo "== Teste Rootless Docker =="
docker info | grep -i rootless || {
  echo "❌ Rootless Docker scheint nicht aktiv zu sein"
  exit 1
}

echo "== Fertig ✅ =="
echo "➡ Neues Terminal öffnen oder: source ~/.bashrc"
echo "➡ Test: docker run hello-world"