#!/bin/bash

#####################################################################
# SSH Panel v5 - Complete Installation Script
# Features: SSH + VMess + Outline VPN Management
# Fixes: Port 80 VMess, Outline auto-start, SSH online detection
#####################################################################

set -e

# Colors

# Auto-detect domain
DOMAIN="panel-$(hostname -I | awk '{print $1}' | tr . -).local"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (sudo)"
    exit 1
fi

print_header "SSH Panel v5 Installer"

# Get domain
echo -e "${YELLOW}Enter your domain (e.g., ssh.example.com):${NC}"



print_header "Installing System Dependencies"

# Update system
apt-get update
apt-get install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx \
    qrencode jq curl wget git shadowsocks-libev sshpass unzip

print_success "System dependencies installed"

print_header "Installing Xray for VMess"

# Install Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

print_success "Xray installed"

print_header "Setting Up Panel Application"

# Get script directory FIRST (before changing directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create panel directory
PANEL_DIR="/opt/ssh-panel"
mkdir -p $PANEL_DIR

# Copy application files
cp $SCRIPT_DIR/app.py $PANEL_DIR/
cp $SCRIPT_DIR/models.py $PANEL_DIR/
cp $SCRIPT_DIR/requirements.txt $PANEL_DIR/
cp -r $SCRIPT_DIR/templates $PANEL_DIR/
mkdir -p $PANEL_DIR/static

# Change to panel directory for setup
cd $PANEL_DIR

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt

print_success "Panel application set up"

# Create instance directory for database
mkdir -p instance

print_header "Configuring Database"

# Initialize database
venv/bin/python3 << PYINIT
from app import app, db
from models import Admin, ServerConfig
import secrets
import string

with app.app_context():
    # Create tables
    db.create_all()
    
    # Generate admin credentials
    admin_user = 'admin_' + ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(6))
    admin_pass = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(22))
    
    # Create admin if not exists
    if not Admin.query.filter_by(username=admin_user).first():
        admin = Admin(username=admin_user)
        admin.set_password(admin_pass)
        db.session.add(admin)
    
    # Set default server config
    configs = {
        'vmess_address': '$(curl -s ifconfig.me)',
        'vmess_port': '80',
        'vmess_path': '/ws',
        'vmess_host': '$DOMAIN',
        'vmess_tls': 'none'
    }
    
    for key, value in configs.items():
        config = ServerConfig.query.filter_by(key=key).first()
        if not config:
            config = ServerConfig(key=key, value=value)
            db.session.add(config)
    
    db.session.commit()
    
    print("=" * 60)
    print("ADMIN CREDENTIALS")
    print("=" * 60)
    print(f"Username: {admin_user}")
    print(f"Password: {admin_pass}")
    print("=" * 60)
    print()
    print("⚠️  SAVE THESE CREDENTIALS! They will not be shown again.")
    print()
    
    # Save to file
    with open('/root/ssh-panel-credentials.txt', 'w') as f:
        f.write(f"SSH Panel Admin Credentials\n")
        import urllib.request
        try:
            ip = urllib.request.urlopen('https://api.ipify.org').read().decode('utf8')
        except:
            ip = "YOUR_VPS_IP"
        f.write(f"Panel URL: http://{ip}\n")
        f.write(f"Username: {admin_user}\n")
        f.write(f"Password: {admin_pass}\n")
PYINIT

deactivate

print_success "Database configured"
print_warning "Credentials saved to: /root/ssh-panel-credentials.txt"

print_header "Creating Management Scripts"

# Create scripts directory
mkdir -p $PANEL_DIR/scripts

# Copy scripts from source
cp $SCRIPT_DIR/scripts/*.sh $PANEL_DIR/scripts/
cp $SCRIPT_DIR/scripts/*.py $PANEL_DIR/scripts/
chmod +x $PANEL_DIR/scripts/*

print_success "Management scripts created"

print_header "Configuring Nginx"

# HTTP-only configuration (SSL can be added later)
cat > /etc/nginx/sites-available/ssh-panel << 'NGINXCONF'
# Port 80 - HTTP (Panel + VMess WebSocket)
server {
    listen 80;
    server_name $DOMAIN;
    
    client_max_body_size 100M;
    
    # Panel
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # VMess WebSocket (NO HTTPS redirect yet)
    location /ws {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300;
    }
}
NGINXCONF

# Enable site
ln -sf /etc/nginx/sites-available/ssh-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config (should pass now - no SSL yet)
nginx -t

print_success "Nginx configured"

# SSL SKIPPED - Run later: sudo certbot --nginx -d YOUR_DOMAIN --email YOUR_EMAIL

# Stage 2: Update config to separate Panel redirect from VMess WebSocket



print_header "Creating Systemd Service"

# Create systemd service
cat > /etc/systemd/system/ssh-panel.service << SYSTEMDSERVICE
[Unit]
Description=SSH Panel
After=network.target

[Service]
Type=notify
User=root
Group=root
WorkingDirectory=$PANEL_DIR
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$PANEL_DIR/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMDSERVICE

# Enable and start services
systemctl daemon-reload
systemctl enable ssh-panel
systemctl enable xray
systemctl start xray
systemctl start ssh-panel

print_success "Services configured and started"

print_header "Configuring SSH Server"

# Enable password authentication
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

# Set default banner
cat > /etc/ssh/banner.txt << 'BANNER'
\033[1;32m
╔════════════════════════════╗
║   WELCOME TO SSH SERVER    ║
╚════════════════════════════╝
\033[0m

\033[1;33m⚠️  WARNING: Authorized Access Only\033[0m

\033[36mServer: SSH Panel
Status: \033[1;32mOnline\033[0m
BANNER

# Enable banner
sed -i 's|^#*Banner.*|Banner /etc/ssh/banner.txt|' /etc/ssh/sshd_config

# Restart SSH
systemctl restart ssh

print_success "SSH server configured"

print_header "Configuring Firewall"

# Configure UFW
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw reload

print_success "Firewall configured"

print_header "Installation Complete!"

# Show credentials
cat /root/ssh-panel-credentials.txt

echo ""
print_success "Panel URL: http://$(curl -s ifconfig.me)"
print_success "Credentials saved: /root/ssh-panel-credentials.txt"
echo ""
print_warning "Features:"
echo "  ✅ SSH User Management (with online/offline detection)"
echo "  ✅ VMess Management (Port 80 + 443 WebSocket)"
echo "  ✅ Outline VPN Management (Auto-start shadowsocks)"
echo "  ✅ QR Code Generation"
echo "  ✅ Config Export"
echo ""
print_warning "Services Status:"
systemctl status ssh-panel --no-pager -l | head -3
systemctl status xray --no-pager -l | head -3
systemctl status nginx --no-pager -l | head -3
echo ""
print_success "Installation finished! Access your panel at https://$DOMAIN"
