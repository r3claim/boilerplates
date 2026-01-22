#!/usr/bin/env bash
set -euo pipefail

MODE="update"

if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
fi

# Sicherheit: nicht als root
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERROR] Dieses Skript darf NICHT als root ausgeführt werden."
  exit 1
fi

check_version() {
  echo "[INFO] Prüfe Rootless Docker Version"
  echo

  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker CLI nicht gefunden"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker Daemon nicht erreichbar"
    exit 1
  fi

  echo "[OK] Docker CLI:"
  docker --version
  echo

  echo "[OK] Docker Daemon:"
  dockerd --version
  echo

  echo "[INFO] Rootless Status:"
  docker info | grep -Ei 'rootless|docker root dir|security options' || true

  echo
  echo "[OK] Check abgeschlossen."
}

do_update() {
  echo "[INFO] Update Rootless Docker"
  echo

  curl -fsSL https://get.docker.com/rootless | sh

  echo
  echo "[INFO] Neustart Rootless Docker Daemon"
  systemctl --user restart docker

  echo
  echo "[OK] Update abgeschlossen"
  echo

  check_version
}

case "$MODE" in
  check)
    check_version
    ;;
  update)
    do_update
    ;;
esac