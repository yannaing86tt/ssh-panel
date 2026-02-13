#!/bin/bash
PORT=$1
PASSWORD=$2
METHOD=${3:-chacha20-ietf-poly1305}

SERVICE_NAME="shadowsocks-$PORT"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Create systemd service
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Shadowsocks Server (Port $PORT)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ss-server -s 0.0.0.0 -p $PORT -k $PASSWORD -m $METHOD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Open firewall
ufw allow "$PORT/tcp" 2>/dev/null
ufw allow "$PORT/udp" 2>/dev/null

echo "✓ Shadowsocks server started on port $PORT"
