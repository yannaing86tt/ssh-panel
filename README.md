# SSH Management Panel - Production Ready

Complete SSH/VMess/Outline VPN management panel with web interface.

## Features

✅ **SSH User Management**
- Create/delete SSH users
- Set expiry dates (1-365 days)
- Max connections limit (1-100)
- Online/offline status monitoring
- Device count tracking
- SSH config generator
- QR code generation
- SSH banner customization

✅ **VMess VPN (Xray-core)**
- Create/delete VMess users
- Auto-generate UUID
- WebSocket transport (/ws)
- HTTPS/TLS support (port 443)
- HTTP fallback (port 80)
- Data usage tracking
- Expiry date management
- QR code generation
- v2rayNG/v2rayN compatible

✅ **Outline VPN (Shadowsocks)**
- Create/delete Outline users
- Auto-start Shadowsocks servers
- chacha20-ietf-poly1305 encryption
- Sequential port assignment (8388+)
- Data usage tracking
- Access key generation (ss:// format)
- QR code generation
- Auto-firewall configuration

✅ **Web Interface**
- Dark theme UI (Bootstrap 5)
- Mobile-responsive design
- Real-time system monitoring
- Auto-refresh status
- Secure admin authentication
- SSL/HTTPS enabled

## Quick Install

### One-Command Installation

```bash
curl -sSL https://raw.githubusercontent.com/yannaing86tt/ssh-panel/main/deploy.sh | bash
```

### Manual Installation

1. **Download installer:**
```bash
wget https://raw.githubusercontent.com/yannaing86tt/ssh-panel/main/deploy.sh
chmod +x deploy.sh
```

2. **Run installer:**
```bash
bash deploy.sh
```

3. **Enter domain when prompted:**
```
Enter domain name: ssh.yourdomain.com
```

4. **Wait 2-3 minutes** for complete installation

5. **Access panel** with generated credentials

## Requirements

- **OS:** Ubuntu 20.04+ / Debian 11+
- **RAM:** 1GB minimum (2GB recommended)
- **Disk:** 10GB minimum
- **Network:** Public IP address
- **Domain:** Pointed to server IP (A record)
- **Ports:** 22, 80, 443, 8388-8395 (open)

## Post-Installation

After installation completes, you'll see:

```
╔════════════════════════════════════════════╗
║        Installation Complete! ✅           ║
╚════════════════════════════════════════════╝

Panel URL:      https://ssh.yourdomain.com
Admin User:     admin_abc123
Admin Password: randomGeneratedPassword==

Services Status:
  Panel:  active
  Nginx:  active
  Xray:   active
```

**Credentials saved to:** `/root/panel-credentials.txt`

## Usage

### SSH Users

1. Go to **SSH Users** → **Create SSH User**
2. Fill form:
   - Username (alphanumeric + underscore)
   - Password
   - Expiry days (1-365)
   - Max connections (1-100)
3. Click **Create User**
4. Download config or scan QR code

### VMess Users

1. Go to **VMess Users** → **Create VMess User**
2. Fill form:
   - Name
   - Data limit (GB)
   - Expiry days
3. Click **Create User**
4. Click **Generate Link** or scan QR code
5. Import to v2rayNG/v2rayN client

**VMess Config:**
- Server: Your server IP
- Port: 443 (HTTPS) or 80 (HTTP)
- Network: WebSocket (ws)
- Path: /ws
- TLS: Enabled (port 443) or Disabled (port 80)

### Outline VPN

1. Go to **Outline Users** → Create form
2. Fill form:
   - Name
   - Data limit (GB)
3. Click **Create User**
4. **Server auto-starts automatically** 
5. Click **Get Key** and copy ss:// link
6. Import to Outline client or scan QR code

**Outline Config:**
- Server: Your server IP
- Port: Auto-assigned (8388, 8389, 8390...)
- Method: chacha20-ietf-poly1305
- Note: Each user needs unique port (protocol limitation)

## Architecture

```
Client → Nginx (443/80) → Backend Services
                         ├→ Flask Panel (5000)
                         ├→ Xray VMess (10000) [/ws path]
                         └→ Shadowsocks (8388+)
```

## File Structure

```
/opt/ssh-panel/
├── app.py                 # Flask application
├── models.py              # Database models
├── requirements.txt       # Python dependencies
├── .env                   # Admin credentials
├── venv/                  # Python virtual environment
├── instance/
│   └── ssh_panel.db       # SQLite database
├── templates/             # HTML templates
│   ├── base.html
│   ├── login.html
│   ├── index.html
│   ├── users.html         # SSH users
│   ├── create_user.html
│   ├── vmess_list.html
│   ├── vmess_create.html
│   ├── vmess_settings.html
│   ├── outline_users.html
│   ├── outline_settings.html
│   └── banner.html
└── scripts/               # Helper scripts
    ├── manage_ssh_user.sh
    ├── generate_ssh_config.sh
    ├── generate_qr.py
    ├── start_outline_server.sh
    ├── delete_outline_server.sh
    ├── generate_outline_key.py
    └── generate_vmess_link.py
```

## Services

### Panel Service
```bash
systemctl status ssh-panel
systemctl restart ssh-panel
journalctl -u ssh-panel -f
```

### Xray (VMess)
```bash
systemctl status xray
systemctl restart xray
journalctl -u xray -f
```

### Shadowsocks (per user)
```bash
systemctl status shadowsocks-8388
systemctl restart shadowsocks-{PORT}
journalctl -u shadowsocks-{PORT} -f
```

### Nginx
```bash
systemctl status nginx
nginx -t  # Test config
systemctl reload nginx
```

## Troubleshooting

### Panel not accessible
```bash
# Check service status
systemctl status ssh-panel nginx

# Check if ports are listening
ss -tulnp | grep -E ":(80|443|5000)"

# Check logs
journalctl -u ssh-panel -n 50
tail -f /var/log/nginx/error.log
```

### SSH user creation fails
```bash
# Verify scripts are executable
chmod +x /opt/ssh-panel/scripts/*.sh
chmod +x /opt/ssh-panel/scripts/*.py

# Check PATH in service
systemctl cat ssh-panel | grep Environment

# Test script manually
cd /opt/ssh-panel
bash scripts/manage_ssh_user.sh create testuser testpass 30 2
```

### VMess not connecting
```bash
# Check Xray status
systemctl status xray

# Verify Xray config
cat /usr/local/etc/xray/config.json

# Check if UUID exists in config
grep "UUID_HERE" /usr/local/etc/xray/config.json

# Test WebSocket endpoint
curl -I https://your-domain.com/ws
```

### Outline not connecting
```bash
# Check Shadowsocks service
systemctl status shadowsocks-8388

# Verify port is listening on 0.0.0.0 (not 127.0.0.1)
ss -tulnp | grep 8388

# Check firewall
ufw status | grep 8388

# Restart service
systemctl restart shadowsocks-{PORT}
```

### SSL certificate issues
```bash
# Renew certificate
certbot renew

# Check certificate status
certbot certificates

# Manual certificate installation
certbot --nginx -d your-domain.com
```

## Security

- ✅ Admin password hashing (Werkzeug)
- ✅ Flask session security (secret key)
- ✅ HTTPS/SSL encryption (Let's Encrypt)
- ✅ UFW firewall enabled
- ✅ Nginx reverse proxy
- ✅ Non-root user execution (services)
- ✅ Auto-generated credentials

**Recommendations:**
1. Change default admin password after first login
2. Use strong, unique passwords for users
3. Enable fail2ban for SSH brute-force protection
4. Regular backups of `/opt/ssh-panel/instance/ssh_panel.db`
5. Monitor logs for suspicious activity

## Backup & Restore

### Backup
```bash
cd /opt/ssh-panel
tar czf ssh-panel-backup-$(date +%Y%m%d).tar.gz \
    instance/ .env

# Copy to safe location
mv ssh-panel-backup-*.tar.gz /root/backups/
```

### Restore
```bash
cd /opt/ssh-panel
tar xzf /path/to/backup.tar.gz

# Restart services
systemctl restart ssh-panel xray shadowsocks-*
```

## Uninstall

```bash
# Stop services
systemctl stop ssh-panel xray shadowsocks-* nginx

# Remove files
rm -rf /opt/ssh-panel
rm /etc/systemd/system/ssh-panel.service
rm /etc/nginx/sites-available/ssh-panel
rm /etc/nginx/sites-enabled/ssh-panel

# Remove packages (optional)
apt remove --purge python3-venv nginx certbot shadowsocks-libev

# Remove Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove

# Reload systemd
systemctl daemon-reload
```

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/yannaing86tt/ssh-panel/issues
- Documentation: https://github.com/yannaing86tt/ssh-panel/wiki

## License

MIT License - Feel free to use, modify, and distribute.

## Credits

- **Flask** - Python web framework
- **Xray-core** - VMess protocol implementation
- **Shadowsocks-libev** - Outline VPN backend
- **Bootstrap 5** - UI framework
- **Let's Encrypt** - Free SSL certificates

---

**Made with ❤️ for easy VPN management**
