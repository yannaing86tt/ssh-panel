#!/bin/bash
USERNAME=$1
PASSWORD=$2
PORT=$3

SERVICE_NAME="shadowsocks-$USERNAME"

# Create systemd service
cat > /etc/systemd/system/$SERVICE_NAME.service << SERVICEEOF
[Unit]
Description=Shadowsocks Server for $USERNAME
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -s 0.0.0.0 -p $PORT -k $PASSWORD -m chacha20-ietf-poly1305
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Reload systemd and start service
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Open firewall
ufw allow $PORT/tcp 2>/dev/null
ufw allow $PORT/udp 2>/dev/null

echo "Outline server started for $USERNAME on port $PORT"
