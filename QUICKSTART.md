# Quick Start Guide

## Installation (2 minutes)

### 1. Prepare DNS
Point your domain to your server IP:
```
Type: A
Name: ssh (or your subdomain)
Value: YOUR_SERVER_IP
TTL: 300
```

### 2. Run installer
```bash
wget https://raw.githubusercontent.com/yannaing86tt/ssh-panel/main/deploy.sh
chmod +x deploy.sh
sudo bash deploy.sh
```

### 3. Enter domain
```
Enter domain name: ssh.yourdomain.com
```

### 4. Wait for completion
Installation takes ~2-3 minutes

### 5. Access panel
```
Panel URL: https://ssh.yourdomain.com
Username: admin_XXXXXX (shown after install)
Password: xxxxxxxxxxxxxxx== (shown after install)
```

## First Steps

### Create SSH User
1. Login to panel
2. Go to **SSH Users** → **Create SSH User**
3. Fill form:
   - Username: `testuser`
   - Password: `secure123`
   - Expiry: `30` days
   - Max connections: `2`
4. Click **Create User**
5. Download config or scan QR code

### Create VMess User
1. Go to **VMess Users** → **Create VMess User**
2. Fill form:
   - Name: `TestVPN`
   - Data limit: `10` GB
   - Expiry: `30` days
3. Click **Create User**
4. Click **Generate Link**
5. Copy `vmess://...` link
6. Import to v2rayNG/v2rayN app

### Create Outline User
1. Go to **Outline Users**
2. Fill form at top:
   - Name: `MyVPN`
   - Data limit: `10` GB
3. Click **Create User**
4. Click **Get Key** button
5. Copy `ss://...` link
6. Import to Outline app or scan QR code

## Client Apps

### SSH
- **Windows:** PuTTY, MobaXterm
- **Android:** HTTP Injector, HTTP Custom, eProxy
- **iOS:** Shadowrocket (SSH tunnel mode)

### VMess
- **Windows:** v2rayN
- **Android:** v2rayNG
- **iOS:** Shadowrocket, Quantumult X
- **macOS:** V2RayXS

### Outline
- **All Platforms:** Outline Client (official)
  - Download: https://getoutline.org/get-started/

## Troubleshooting

### Panel not accessible
```bash
systemctl status ssh-panel nginx
journalctl -u ssh-panel -n 50
```

### SSL certificate failed
```bash
certbot --nginx -d your-domain.com
```

### User creation not working
```bash
chmod +x /opt/ssh-panel/scripts/*.sh
systemctl restart ssh-panel
```

## Support

- GitHub Issues: https://github.com/yannaing86tt/ssh-panel/issues
- Documentation: See README.md
- Credentials: /root/panel-credentials.txt
