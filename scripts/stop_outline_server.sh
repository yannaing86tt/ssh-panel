#!/bin/bash
USERNAME=$1

SERVICE_NAME="shadowsocks-$USERNAME"

# Stop and disable service
systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null

# Remove service file
rm -f /etc/systemd/system/$SERVICE_NAME.service

# Reload systemd
systemctl daemon-reload

echo "Outline server stopped for $USERNAME"
