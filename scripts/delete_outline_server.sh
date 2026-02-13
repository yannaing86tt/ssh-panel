#!/bin/bash
PORT=$1
SERVICE_NAME="shadowsocks-$PORT"

systemctl stop "$SERVICE_NAME" 2>/dev/null
systemctl disable "$SERVICE_NAME" 2>/dev/null
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload

echo "✓ Shadowsocks server on port $PORT deleted"
