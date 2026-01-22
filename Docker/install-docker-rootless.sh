#!/usr/bin/env bash
# install-docker-rootless.sh
# Run as root.
set -euo pipefail

USER_NAME="dockeruser"
SUBID_BLOCK_SIZE=65536
INITIAL_SUBID=100000

info()  { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn()  { printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
error() { printf "\e[1;31m[ERROR]\e[0m %s\n" "$*"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  error "Dieses Skript muss als root ausgeführt werden."
fi

# 1) Install basic prerequisites (uidmap, slirp4netns, fuse-overlayfs, dbus-user-session, curl)
install_prereqs() {
  info "Ermittle Paketmanager..."
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    info "apt detected — updating and installing prerequisites..."
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl uidmap dbus-user-session slirp4netns fuse-overlayfs
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    info "dnf detected — installing prerequisites..."
    dnf install -y shadow-utils uidmap dbus-user-session slirp4netns fuse-overlayfs curl
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
    info "pacman detected — installing prerequisites..."
    pacman -Syu --noconfirm uidmap dbus-user-session slirp4netns fuse-overlayfs curl
  else
    warn "Kein bekannter Paketmanager gefunden (apt/dnf/pacman). Bitte installiere manuell: uidmap (newuidmap/newgidmap), slirp4netns, fuse-overlayfs, dbus-user-session, curl."
  fi
}

# 2) Install Docker Engine (rootful) using get.docker.com (official easy installer)
install_docker_engine() {
  info "Installiere Docker Engine (offizielles Installationsskript)..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
}

# 3) Stop/disable system docker + remove socket (per Docker docs recommendation)
disable_system_docker() {
  info "Stoppe und deaktiviere systemweiten Docker (service + socket) und entferne den root socket..."
  # try best effort; ignore failures
  systemctl disable --now docker.service docker.socket || true
  systemctl stop docker.service docker.socket || true
  # Maskiere socket so dass systemd nicht mehr via socket-activation startet
  systemctl mask docker.socket || true
  systemctl mask docker.service || true
  rm -f /var/run/docker.sock || true
  info "System Docker sollte nun deaktiviert / der Socket entfernt sein."
}

# 4) Create user without sudo
create_user_no_sudo() {
  if id "${USER_NAME}" >/dev/null 2>&1; then
    info "User ${USER_NAME} existiert bereits — überspringe Erstellung."
  else
    info "Erstelle Benutzer ${USER_NAME} (kein sudo)..."
    useradd -m -s /bin/bash "${USER_NAME}"
    # Sperre Passwort (kein interaktives passwort)
    passwd -l "${USER_NAME}" >/dev/null 2>&1 || true
    info "Benutzer ${USER_NAME} erstellt (Passwort gesperrt)."
  fi
}

# Utility: check overlap in /etc/subuid /etc/subgid
range_overlaps() {
  local start=$1 end=$2 file=$3
  # file lines: name:start:count
  while IFS=: read -r name s count; do
    [ -z "$s" ] && continue
    existing_start=$s
    existing_end=$((existing_start + count - 1))
    if ! (("$end" < "$existing_start" || "$start" > "$existing_end")); then
      return 0  # overlaps
    fi
  done < <(grep -E '^[^#]+' "$file" 2>/dev/null || true)
  return 1  # no overlap
}

# 5) Ensure /etc/subuid and /etc/subgid contain a block for the user (65536)
ensure_subid_ranges() {
  for file in /etc/subuid /etc/subgid; do
    if grep -q "^${USER_NAME}:" "$file" 2>/dev/null; then
      info "${file} enthält bereits Eintrag für ${USER_NAME}."
      continue
    fi

    candidate=${INITIAL_SUBID}
    while true; do
      candidate_end=$((candidate + SUBID_BLOCK_SIZE - 1))
      if range_overlaps "$candidate" "$candidate_end" "$file"; then
        candidate=$((candidate + SUBID_BLOCK_SIZE))
        # try next block
        continue
      else
        # append
        info "Füge ${USER_NAME}:${candidate}:${SUBID_BLOCK_SIZE} zu ${file} hinzu."
        printf "%s:%d:%d\n" "${USER_NAME}" "${candidate}" "${SUBID_BLOCK_SIZE}" >> "$file"
        break
      fi
    done
  done
}

# 6) Install/enable rootless Docker for the user
install_rootless_for_user() {
  # if dockerd-rootless-setuptool.sh exists, prefer using it
  if [ -x /usr/bin/dockerd-rootless-setuptool.sh ]; then
    info "Found /usr/bin/dockerd-rootless-setuptool.sh — Verwende dieses Tool für die Installation (als ${USER_NAME})."
    su - "${USER_NAME}" -c "mkdir -p \"\$HOME/bin\" && /usr/bin/dockerd-rootless-setuptool.sh install"
  else
    info "Kein dockerd-rootless-setuptool.sh gefunden — benutze das offizielle rootless Installationsskript (get.docker.com/rootless) als ${USER_NAME}."
    # run the rootless script as the user (non-root)
    su - "${USER_NAME}" -c "curl -fsSL https://get.docker.com/rootless | sh"
  fi

  info "Erlaube 'linger' damit der Benutzerdämon auch ohne interaktive Login-Sitzung laufen kann."
  # enable linger so systemd --user services can run after reboot
  loginctl enable-linger "${USER_NAME}" || warn "loginctl enable-linger schlug fehl (eventuell auf dieser Plattform nicht verfügbar)."
}

# 7) Final info / environment hint
print_final_instructions() {
  uid=$(id -u "${USER_NAME}")
  info "Fertig. Wichtige Hinweise für den Benutzer ${USER_NAME}:"
  echo
  cat <<EOF
Als ${USER_NAME} evtl. nötig (oder in ~/.bashrc eintragen):

  export PATH=\$HOME/bin:\$PATH
  export DOCKER_HOST=unix:///run/user/${uid}/docker.sock

Beispiel (als ${USER_NAME}):
  su - ${USER_NAME} -c 'docker info'

Wenn 'docker info' auf den rootless Daemon zugreift, sollte in der Ausgabe 'rootless' bei Security Options stehen.

Quellen:
 - Docker Rootless Dokumentation (Prüfungen, Hinweise, wie man deaktivierten system Docker behandelt). 
 - Offizielles rootless Installationsskript: https://get.docker.com/rootless

EOF
}

main() {
  install_prereqs
  install_docker_engine
  disable_system_docker
  create_user_no_sudo
  ensure_subid_ranges
  install_rootless_for_user
  print_final_instructions
}

main "$@"