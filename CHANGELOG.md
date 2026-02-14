# Changelog - SSH Panel

All notable changes to this project will be documented in this file.

## [5.0.0] - 2026-02-14

### 🎉 Major Release - Production Ready

### ✅ Fixed
- **VMess Port 80 WebSocket** - Fixed Certbot HTTPS redirect blocking /ws endpoint
  - Nginx config now bypasses redirect for /ws path
  - Both port 80 (HTTP) and 443 (HTTPS) work correctly
  
- **Outline VPN Auto-Start** - Fixed Shadowsocks service not starting
  - Services now bind to 0.0.0.0 instead of 127.0.0.1
  - Systemd services auto-start on boot
  - Firewall ports auto-open
  
- **SSH Online Detection** - Fixed users always showing "Offline"
  - Route now attaches connection stats to user objects
  - Real-time online/offline status display
  - Accurate device count per user

### 🆕 Added
- Single-command installation script
- Auto-generated secure admin credentials
- Comprehensive documentation (README.md)
- Production-ready systemd services
- Automatic SSL certificate via Certbot
- UFW firewall configuration

### 🔧 Changed
- Nginx configuration optimized for WebSocket
- Improved error handling in management scripts
- Better service management with proper PATH environment
- Enhanced database initialization

### 📦 Package
- All-in-one installer (install.sh)
- Pre-configured templates and static files
- Management scripts for SSH/VMess/Outline
- Complete Python dependencies

---

## [4.0.0] - 2026-02-13

### Known Issues (Fixed in v5)
- ❌ VMess port 80 not working (HTTPS redirect)
- ❌ Outline keys not connecting (wrong binding)
- ❌ SSH users showing offline (missing stats)

### Features
- SSH user management
- VMess user management
- Outline VPN user management
- QR code generation
- Config export

---

## Installation

```bash
cd ssh-panel-v5-repo
bash install.sh
```

See README.md for full documentation.
