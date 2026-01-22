#!/bin/bash
set -e

echo "Installiere chrony..."
apt update
apt install -y chrony

echo "Konfiguriere NTP-Server..."
cat >> /etc/chrony/chrony.conf << 'EOF'
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
