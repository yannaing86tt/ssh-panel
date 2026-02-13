# Changelog

## Version 2.0.0 (2026-02-13)

### Added
- ✅ Complete auto-deployment script
- ✅ SSH user management (create/delete/extend)
- ✅ VMess VPN management (Xray-core)
- ✅ Outline VPN management (Shadowsocks)
- ✅ Auto-start Shadowsocks servers on user creation
- ✅ SSL/HTTPS automatic installation
- ✅ Nginx reverse proxy configuration
- ✅ Firewall auto-configuration
- ✅ QR code generation for all VPN types
- ✅ Real-time connection monitoring
- ✅ Data usage tracking
- ✅ Mobile-responsive UI
- ✅ Dark theme interface
- ✅ SSH banner customization
- ✅ Systemd service integration

### Fixed
- ✅ VMess connection issues (port conflict resolved)
- ✅ Outline server binding (0.0.0.0 instead of localhost)
- ✅ SSH user creation PATH environment
- ✅ Database path configuration (absolute paths)
- ✅ Script permissions on deployment
- ✅ Service auto-restart on failure

### Technical Details
- Flask 3.0.0 + SQLAlchemy
- Xray-core 1.8.16
- Shadowsocks-libev 3.3.5+
- Bootstrap 5 UI framework
- Let's Encrypt SSL
- Gunicorn WSGI server

## Version 1.0.0 (Initial Release)

- Basic SSH panel with limited features
- Manual configuration required
- No VPN management
