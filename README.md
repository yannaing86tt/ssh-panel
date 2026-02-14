# SSH Panel v5 - Production Ready

Complete SSH, VMess, and Outline VPN management panel with all bugs fixed.

## Features

✅ **SSH User Management**
- Create/Delete SSH accounts
- Set expiry dates and connection limits
- **Real-time online/offline status detection** (FIXED)
- Active connection count per user
- Custom SSH banner with ANSI colors

✅ **VMess Management (Xray)**
- Create VMess users with WebSocket
- **Port 80 support (HTTP)** (FIXED)
- Port 443 support (HTTPS/TLS)
- Auto-generate UUID and QR codes
- Config export

✅ **Outline VPN Management**
- Create Shadowsocks users
- **Auto-start with systemd services** (FIXED)
- **Correct binding to 0.0.0.0** (FIXED)
- Sequential port assignment (8388+)
- Access key generation with QR codes

## Fixed Bugs

### 1. VMess Port 80 Not Working
**Problem:** Certbot HTTPS redirect blocked /ws endpoint on port 80

**Fix:** Nginx config now bypasses HTTPS redirect for /ws path:
```nginx
location /ws {
    # Direct proxy to Xray, no redirect
    proxy_pass http://127.0.0.1:10000;
}
```

### 2. Outline Keys Not Connecting
**Problem:** Shadowsocks binding to 127.0.0.1 instead of 0.0.0.0

**Fix:** Service binds to all interfaces:
```bash
ExecStart=/usr/bin/ss-server -s 0.0.0.0 -p $PORT ...
```

### 3. SSH Users Showing Offline
**Problem:** Connection stats not attached to user objects

**Fix:** Route now attaches stats dynamically:
```python
for user in all_users:
    stats = user_stats.get(user.username, {...})
    user.is_online = (stats['status'] == 'online')
    user.device_count = stats['device_count']
```

## Installation

### Requirements
- Fresh Ubuntu 20.04/22.04 VPS
- Root access
- Domain pointing to VPS IP
- Ports 22, 80, 443 open

### Quick Install

```bash
# Download package
wget https://[YOUR_URL]/ssh-panel-v5.tar.gz
tar -xzf ssh-panel-v5.tar.gz
cd ssh-panel-v5

# Run installer
chmod +x install.sh
./install.sh
```

During installation you'll be asked for:
- Domain name (e.g., ssh.example.com)
- Email for SSL certificate

### What Gets Installed

- Python 3 + virtualenv
- Nginx (reverse proxy)
- Xray (VMess core)
- Shadowsocks-libev (Outline VPN)
- Certbot (SSL certificates)
- UFW firewall rules

## Default Configuration

### VMess Settings
```
Protocol: VMess
Address: [YOUR_VPS_IP]
Port: 80 (HTTP) or 443 (HTTPS)
Network: WebSocket (ws)
Path: /ws
TLS: none (port 80) or tls (port 443)
```

### Outline Settings
```
Method: chacha20-ietf-poly1305
Server: [YOUR_VPS_IP]
Ports: 8388, 8389, 8390... (sequential)
Binding: 0.0.0.0 (all interfaces)
```

### SSH Settings
```
Port: 22
Auth: Password
Shell: /bin/bash
Banner: Custom ANSI banner
```

## Post-Installation

1. Access panel: `https://your-domain.com`
2. Login with generated admin credentials
3. Credentials saved at: `/root/ssh-panel-credentials.txt`

## Usage

### Creating SSH User
1. Go to "SSH Users" page
2. Click "Create"
3. Set username, password, expiry, max connections
4. User can connect via: `ssh username@your-domain.com`

### Creating VMess User
1. Go to "VMess Users" page  
2. Click "Create"
3. Enter name, expiry date
4. Scan QR code or copy link
5. Import to v2rayNG/v2rayN client

### Creating Outline User
1. Go to "Outline VPN" page
2. Click "Create"
3. Enter name, expiry date
4. Scan QR code or copy access key
5. Import to Outline client

## Troubleshooting

### VMess not connecting on port 80
- Check Nginx config: `/etc/nginx/sites-available/ssh-panel`
- Verify /ws location block exists
- Test: `curl -I http://your-domain.com/ws` should NOT redirect

### Outline VPN not connecting
- Check service: `systemctl status shadowsocks-outline-8388`
- Verify binding: `ss -tulnp | grep 8388` should show `0.0.0.0:8388`
- Check firewall: `ufw status | grep 8388`

### SSH showing offline
- Refresh page after connecting
- Check function: Route attaches connection stats
- Verify SSH session: `ps aux | grep "sshd: username"`

## File Structure

```
/opt/ssh-panel/
├── app.py              # Main Flask application
├── models.py           # Database models
├── requirements.txt    # Python dependencies
├── templates/          # HTML templates
├── static/            # CSS/JS assets
├── scripts/           # Management scripts
│   ├── manage_ssh_user.sh
│   ├── manage_vmess_user.sh
│   └── manage_outline_user.sh
├── venv/              # Python virtual environment
└── instance/
    └── ssh_panel.db   # SQLite database

/etc/nginx/sites-available/
└── ssh-panel          # Nginx reverse proxy config

/etc/systemd/system/
├── ssh-panel.service  # Panel service
└── shadowsocks-outline-*.service  # Outline services

/usr/local/etc/xray/
└── config.json        # Xray VMess config
```

## Services

```bash
# Panel
systemctl status ssh-panel
systemctl restart ssh-panel

# VMess
systemctl status xray
systemctl restart xray

# Outline (per-user)
systemctl status shadowsocks-outline-8388
systemctl restart shadowsocks-outline-8388

# Nginx
systemctl status nginx
systemctl reload nginx
```

## Logs

```bash
# Panel logs
journalctl -u ssh-panel -f

# Xray logs
journalctl -u xray -f

# Outline logs
journalctl -u shadowsocks-outline-8388 -f

# Nginx logs
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```

## Security Notes

- Admin password is randomly generated (22 characters)
- SSL/TLS enabled by default (Let's Encrypt)
- UFW firewall configured
- SSH password authentication enabled (required for panel)
- All services run with minimal privileges

## Support

For issues or questions, check:
1. Service status: `systemctl status [service]`
2. Logs: `journalctl -u [service] -n 50`
3. Nginx config: `nginx -t`
4. Database: `/opt/ssh-panel/instance/ssh_panel.db`

## Version History

### v5 (2026-02-14)
- ✅ Fixed VMess port 80 (Nginx /ws bypass)
- ✅ Fixed Outline auto-start (systemd + 0.0.0.0 binding)
- ✅ Fixed SSH online detection (stats attachment)
- ✅ Production-ready installer

### v4 (Previous)
- Initial release with all three features
- Known bugs (now fixed in v5)

## License

Free to use for personal and commercial purposes.
