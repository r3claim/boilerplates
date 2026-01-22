#!/bin/bash
set -e

if [ ! "$(id -u)" -eq 0 ]; then
    echo -e "Fehler: Dieses Skript muss als root / mit sudo ausgeführt werden."
    exit 1
fi

echo "Installiere chrony..."
apt update
apt install -y chrony

echo "Konfiguriere NTP-Server..."
cat > /etc/chrony/conf.d/01-timeserver.conf << 'EOF'
pool 0.de.pool.ntp.org iburst
pool 1.de.pool.ntp.org iburst
pool 2.de.pool.ntp.org iburst
pool 3.de.pool.ntp.org iburst
EOF

echo "Starte chrony neu..."
systemctl enable chrony
systemctl restart chrony

echo "Status:"
chronyc tracking
