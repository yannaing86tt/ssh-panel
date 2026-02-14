# SSH Panel - Quick Install (No SSL)

One-line installation for Ubuntu 22.04+ VPS.

## Installation

```bash
curl -sL https://raw.githubusercontent.com/yannaing86tt/ssh-panel/main/install-no-ssl.sh | bash
```

Or with git clone:

```bash
git clone https://github.com/yannaing86tt/ssh-panel.git && cd ssh-panel && bash install-no-ssl.sh
```

## Features

- ✅ SSH User Management (online/offline detection)
- ✅ VMess Management (Port 80 + 443 WebSocket)
- ✅ Outline VPN Management (Auto-start)
- ✅ QR Code Generation
- ✅ Config Export

## After Installation

1. Get admin credentials:
```bash
cat /root/ssh-panel-credentials.txt
```

2. Get VPS IP:
```bash
curl ifconfig.me
```

3. Access panel:
```
http://YOUR_VPS_IP
```

## Add SSL Later (Optional)

```bash
sudo certbot --nginx -d your-domain.com --email your@email.com
```

## Requirements

- Ubuntu 22.04 or later
- Root access
- Port 80, 443 open

## Installation Time

~5-7 minutes
