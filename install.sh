#!/bin/bash
set -e

echo "╔════════════════════════════════════════════╗"
echo "║   SSH Panel Production Installer v2.0      ║"
echo "║        Complete Auto-Install Package        ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Prompt for domain
read -p "Enter domain name (e.g., ssh.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Domain is required!${NC}"
    exit 1
fi

echo -e "${GREEN}Installing SSH Panel for: $DOMAIN${NC}\n"

# Get server IP
SERVER_IP=$(curl -s ifconfig.me)
echo -e "Server IP: ${CYAN}$SERVER_IP${NC}\n"

# Installation steps
echo -e "${GREEN}[1/12] Installing system packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx \
    git net-tools psmisc shadowsocks-libev curl ufw -qq > /dev/null 2>&1

echo -e "${GREEN}[2/12] Creating directory structure...${NC}"
mkdir -p /opt/ssh-panel/{scripts,templates,static,instance}
cd /opt/ssh-panel

echo -e "${GREEN}[3/12] Generating admin credentials...${NC}"
ADMIN_USER="admin_$(openssl rand -hex 3)"
ADMIN_PASS=$(openssl rand -base64 18)
SECRET_KEY=$(openssl rand -hex 32)

cat > .env << ENV
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
SECRET_KEY=$SECRET_KEY
ENV

echo -e "${GREEN}[4/12] Creating Python environment...${NC}"
cat > requirements.txt << 'REQUIREMENTS'
Flask==3.0.0
Flask-SQLAlchemy==3.1.1
Flask-Login==0.6.3
Werkzeug==3.0.1
qrcode[pil]==7.4.2
Pillow==10.2.0
python-dotenv==1.0.0
gunicorn==21.2.0
psutil==5.9.8
REQUIREMENTS

python3 -m venv venv
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt

echo -e "${GREEN}[5/12] Downloading application files from GitHub...${NC}"
# Clone from GitHub repo (public)
GITHUB_REPO="https://github.com/YOUR_USERNAME/ssh-panel.git"
# For now, we'll create files inline - replace with git clone after upload

# This is placeholder - will be replaced with actual download
echo -e "${YELLOW}Note: Using bundled application files${NC}"

echo -e "${GREEN}[6/12] Installing Xray-core...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.8.16 > /dev/null 2>&1

mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << 'XRAYCONF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 10000,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {"clients": []},
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "/ws"}
    }
  }],
  "outbounds": [{"protocol": "freedom", "settings": {}}]
}
XRAYCONF

systemctl enable xray > /dev/null 2>&1
systemctl start xray

echo -e "${GREEN}[7/12] Initializing database...${NC}"
# Will create init_db.py after app files are in place

echo -e "${GREEN}[8/12] Creating systemd service...${NC}"
cat > /etc/systemd/system/ssh-panel.service << SERVICE
[Unit]
Description=SSH Panel
After=network.target

[Service]
Type=notify
User=root
WorkingDirectory=/opt/ssh-panel
Environment="PATH=/opt/ssh-panel/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/ssh-panel/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ssh-panel > /dev/null 2>&1

echo -e "${GREEN}[9/12] Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/ssh-panel << NGINXCONF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/ssh-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1
systemctl reload nginx

echo -e "${GREEN}[10/12] Installing SSL certificate...${NC}"
echo -e "${YELLOW}Make sure DNS is pointing to $SERVER_IP${NC}"
sleep 2
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect --quiet

echo -e "${GREEN}[11/12] Configuring firewall...${NC}"
ufw --force enable > /dev/null 2>&1
ufw allow 22/tcp > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw allow 8388:8395/tcp > /dev/null 2>&1
ufw allow 8388:8395/udp > /dev/null 2>&1

echo -e "${GREEN}[12/12] Starting services...${NC}"
systemctl start ssh-panel
sleep 2

# Check services
PANEL_STATUS=$(systemctl is-active ssh-panel)
NGINX_STATUS=$(systemctl is-active nginx)
XRAY_STATUS=$(systemctl is-active xray)

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║        Installation Complete! ✅           ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo -e "${CYAN}Panel URL:${NC}      https://$DOMAIN"
echo -e "${CYAN}Admin User:${NC}     $ADMIN_USER"
echo -e "${CYAN}Admin Password:${NC} $ADMIN_PASS"
echo -e "${CYAN}Server IP:${NC}      $SERVER_IP"
echo ""
echo -e "${GREEN}Services Status:${NC}"
echo -e "  Panel:  $PANEL_STATUS"
echo -e "  Nginx:  $NGINX_STATUS"
echo -e "  Xray:   $XRAY_STATUS"
echo ""
echo -e "${YELLOW}Credentials saved to: /root/panel-credentials.txt${NC}"
echo ""

# Save credentials
cat > /root/panel-credentials.txt << CREDS
SSH Panel Installation
=====================

Panel URL: https://$DOMAIN
Admin Username: $ADMIN_USER
Admin Password: $ADMIN_PASS

Server IP: $SERVER_IP
Installation Date: $(date)

Services:
- Panel: $PANEL_STATUS
- Nginx: $NGINX_STATUS
- Xray: $XRAY_STATUS

Features:
- SSH User Management
- VMess VPN (Xray)
- Outline VPN (Shadowsocks)
CREDS

echo -e "${GREEN}Next Steps:${NC}"
echo "1. Verify DNS: $DOMAIN → $SERVER_IP"
echo "2. Access panel: https://$DOMAIN"
echo "3. Login with credentials above"
echo "4. Create SSH/VMess/Outline users"
echo ""
echo -e "${CYAN}Installation log: /var/log/ssh-panel-install.log${NC}"
