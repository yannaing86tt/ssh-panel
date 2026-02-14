from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file
from flask_login import LoginManager, login_user, logout_user, login_required, current_user
from models import db, Admin, SSHUser, Connection, ServerConfig
from datetime import datetime, timedelta
from dotenv import load_dotenv
import os
import subprocess
import logging
import psutil
import qrcode
from io import BytesIO
import json

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'default-secret-key-change-this')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:////opt/ssh-panel/instance/ssh_panel.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

# Flask-Login setup
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

@login_manager.user_loader
def load_user(user_id):
    return Admin.query.get(int(user_id))

# Helper functions
def run_command(command):
    """Execute shell command and return output"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def get_system_info():
    """Get server system information"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    return {
        'cpu': cpu_percent,
        'memory_used': memory.percent,
        'memory_total': memory.total / (1024**3),  # GB
        'disk_used': disk.percent,
        'disk_total': disk.total / (1024**3)  # GB
    }

def get_active_connections():
    """Get list of active SSH connections"""
    success, output, _ = run_command("who | grep -v 'tty' | wc -l")
    if success:
        return int(output.strip())
    return 0

def get_user_connection_stats():
    """Get detailed active SSH connections by user and device count (PID-based detection)"""
    import re
    import subprocess as sp
    
    user_stats = {}
    
    # Get all SSH connections
    success, output, _ = run_command("ss -tnp | grep ':22' | grep ESTAB | grep 'sshd'")
    
    if success and output:
        for line in output.strip().split('\n'):
            if not line or 'sshd' not in line:
                continue
                
            # Extract PID from users:(("sshd",pid=1234,fd=4))
            pid_match = re.search(r'pid=(\d+)', line)
            if not pid_match:
                continue
                
            pid = pid_match.group(1)
            
            # Get process info to find username
            try:
                ps_output = sp.run(f"ps -p {pid} -o args=", 
                                  shell=True, capture_output=True, text=True, timeout=2)
                if ps_output.returncode == 0:
                    proc_info = ps_output.stdout.strip()
                    # Format: "sshd: username [priv]" or "sshd: username@pts/0"
                    user_match = re.search(r'sshd:\s*(\w+)', proc_info)
                    if user_match:
                        username = user_match.group(1)
                        # Skip root and unknown
                        if username in ['root', 'unknown']:
                            continue
                        
                        # Extract remote IP from connection line
                        ip_match = re.search(r'([0-9.]+):(\d+)\s+users:', line)
                        if ip_match:
                            remote_ip = ip_match.group(1)
                            
                            if username not in user_stats:
                                user_stats[username] = {'status': 'online', 'devices': set()}
                            user_stats[username]['devices'].add(remote_ip)
            except Exception as e:
                app.logger.error(f"Error checking PID {pid}: {e}")
                continue
    
    # Build final stats for all users
    all_ssh_users = SSHUser.query.all()
    final_stats = {}
    for user in all_ssh_users:
        username = user.username
        if username in user_stats:
            final_stats[username] = {
                'status': 'online',
                'device_count': len(user_stats[username]['devices'])
            }
        else:
            final_stats[username] = {
                'status': 'offline',
                'device_count': 0
            }
    return final_stats


# Routes
@app.route('/')
@login_required
def index():
    """Dashboard"""
    total_users = SSHUser.query.count()
    active_users = SSHUser.query.filter_by(is_active=True).count()
    expired_users = SSHUser.query.filter(SSHUser.expiry_date < datetime.utcnow()).count()
    active_connections = get_active_connections()
    system_info = get_system_info()
    
    return render_template('index.html',
                         total_users=total_users,
                         active_users=active_users,
                         expired_users=expired_users,
                         active_connections=active_connections,
                         system=system_info)

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Admin login"""
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        admin = Admin.query.filter_by(username=username).first()
        if admin and admin.check_password(password):
            login_user(admin)
            return redirect(url_for('index'))
        else:
            flash('Invalid username or password', 'error')
    
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    """Logout"""
    logout_user()
    return redirect(url_for('login'))

@app.route('/users')
@login_required
def users():
    """List all SSH users with connection stats"""
    all_users = SSHUser.query.order_by(SSHUser.created_at.desc()).all()
    user_stats = get_user_connection_stats()
    
    # Attach connection stats to user objects for template
    for user in all_users:
        stats = user_stats.get(user.username, {'status': 'offline', 'device_count': 0})
        user.is_online = (stats['status'] == 'online')
        user.device_count = stats['device_count']
    
    return render_template('users.html', users=all_users, user_stats=user_stats)

@app.route('/settings/banner', methods=['GET', 'POST'])
@login_required
def banner():
    """Manage SSH Banner"""
    banner_config = ServerConfig.query.filter_by(key='ssh_banner').first()
    
    if request.method == 'POST':
        banner_text = request.form.get('banner_text')
        if banner_config:
            banner_config.value = banner_text
        else:
            banner_config = ServerConfig(key='ssh_banner', value=banner_text)
            db.session.add(banner_config)
        
        db.session.commit()
        
        # Apply banner to system
        with open('/tmp/ssh_banner.txt', 'w') as f:
            f.write(banner_text)
        
        # Script to update ssh banner
        run_command("cp /tmp/ssh_banner.txt /etc/ssh/banner.txt")
        run_command("sed -i 's|^#Banner none|Banner /etc/ssh/banner.txt|' /etc/ssh/sshd_config")
        run_command("sed -i 's|^Banner.*|Banner /etc/ssh/banner.txt|' /etc/ssh/sshd_config")
        run_command("systemctl restart ssh")
        
        flash('SSH Banner updated successfully!', 'success')
        return redirect(url_for('banner'))
        
    current_banner = banner_config.value if banner_config else ''
    return render_template('banner.html', current_banner=current_banner)

@app.route('/users/create', methods=['GET', 'POST'])
@login_required
def create_user():
    """Create new SSH user"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        days = int(request.form.get('days', 30))
        max_conn = int(request.form.get('max_connections', 2))
        notes = request.form.get('notes', '')
        
        # Check if user already exists
        if SSHUser.query.filter_by(username=username).first():
            flash(f'User {username} already exists!', 'error')
            return redirect(url_for('create_user'))
        
        # Create system user
        cmd = f'/opt/ssh-panel/scripts/create_ssh_user.sh {username} {password} {days}'
        app.logger.info(f'Executing: {cmd}')
        success, stdout, stderr = run_command(cmd)
        app.logger.info(f'Result: success={success}, stdout={stdout}, stderr={stderr}')
        
        if not success:
            app.logger.error(f'Script failed: {stderr}')
            flash(f'Failed to create system user: {stderr}', 'error')
            return redirect(url_for('create_user'))
        
        # Verify system user was actually created
        verify_success, verify_out, _ = run_command(f'id {username}')
        if not verify_success:
            app.logger.error(f'System user {username} not found after creation!')
            flash(f'System user creation reported success but user not found!', 'error')
            return redirect(url_for('create_user'))
        
        app.logger.info(f'System user verified: {verify_out}')
        
        # Add to database
        expiry_date = datetime.utcnow() + timedelta(days=days)
        new_user = SSHUser(
            username=username,
            password=password,
            expiry_date=expiry_date,
            max_connections=max_conn,
            notes=notes
        )
        db.session.add(new_user)
        db.session.commit()
        
        flash(f'User {username} created successfully!', 'success')
        return redirect(url_for('users'))
    
    return render_template('create_user.html')

@app.route('/users/<int:user_id>/delete', methods=['POST'])
@login_required
def delete_user(user_id):
    """Delete SSH user"""
    user = SSHUser.query.get_or_404(user_id)
    
    # Delete system user
    run_command(f'/opt/ssh-panel/scripts/delete_ssh_user.sh {user.username}')
    
    # Delete from database
    db.session.delete(user)
    db.session.commit()
    
    flash(f'User {user.username} deleted successfully!', 'success')
    return redirect(url_for('users'))

@app.route('/users/<int:user_id>/extend', methods=['POST'])
@login_required
def extend_user(user_id):
    """Extend user expiry date"""
    user = SSHUser.query.get_or_404(user_id)
    days = int(request.form.get('days', 30))
    
    user.expiry_date = user.expiry_date + timedelta(days=days)
    db.session.commit()
    
    flash(f'User {user.username} extended by {days} days!', 'success')
    return redirect(url_for('users'))

@login_required
@login_required
@app.route('/monitor')
@login_required
def monitor():
    """Real-time connection monitoring"""
    connections = Connection.query.all()
    return render_template('monitor.html', connections=connections)

@app.route('/api/system-stats')
@login_required
def api_system_stats():
    """API endpoint for real-time system stats"""
    return jsonify(get_system_info())

@app.route('/api/connections')
@login_required
def api_connections():
    """API endpoint for active connections"""
    # Parse 'who' command output
    success, output, _ = run_command("who | grep -v 'tty'")
    connections = []
    
    if success and output:
        for line in output.strip().split('\n'):
            if line:
                parts = line.split()
                if len(parts) >= 5:
                    connections.append({
                        'username': parts[0],
                        'ip': parts[4].strip('()'),
                        'time': ' '.join(parts[2:4])
                    })
    
    return jsonify(connections)

@app.route('/config/<string:username>')
@login_required
def generate_config(username):
    """Generate SSH config file"""
    user = SSHUser.query.filter_by(username=username).first_or_404()
    server_ip = request.host.split(':')[0]
    
    config_text = f"""# SSH Account Configuration
# Username: {username}
# Password: {user.password}
# Server: {server_ip}
# Port: 22
# Expiry: {user.expiry_date.strftime('%Y-%m-%d')}

# OpenSSH Command:
ssh {username}@{server_ip}

# HTTP Injector Payload:
{username}:{user.password}@{server_ip}:22
"""
    
    return config_text, 200, {'Content-Type': 'text/plain; charset=utf-8',
                               'Content-Disposition': f'attachment; filename={username}_config.txt'}

@app.route('/qr/<string:username>')
@login_required
def generate_qr(username):
    """Generate QR code for SSH config"""
    user = SSHUser.query.filter_by(username=username).first_or_404()
    server_ip = request.host.split(':')[0]
    
    qr_data = f"ssh://{username}:{user.password}@{server_ip}:22"
    
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(qr_data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    buf = BytesIO()
    img.save(buf, format='PNG')
    buf.seek(0)
    
    return send_file(buf, mimetype='image/png')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        
        # Create default admin if not exists
        if not Admin.query.filter_by(username=os.getenv('ADMIN_USERNAME')).first():
            admin = Admin(username=os.getenv('ADMIN_USERNAME'))
            admin.set_password(os.getenv('ADMIN_PASSWORD'))
            db.session.add(admin)
            db.session.commit()
    
    app.run(host='0.0.0.0', port=5000, debug=False)
# VMess Management Routes - Add to app.py

import uuid as uuid_lib
import subprocess

@app.route('/vmess')
@login_required
def vmess_list():
    """List VMess users"""
    from models import VMessUser
    users = VMessUser.query.all()
    return render_template('vmess_list.html', users=users)

@app.route('/vmess/create', methods=['GET', 'POST'])
@login_required
def vmess_create():
    """Create new VMess user"""
    from models import VMessUser
    from datetime import datetime, timedelta
    
    if request.method == 'POST':
        name = request.form.get('name')
        data_limit = int(request.form.get('data_limit', 0))
        expiry_days = int(request.form.get('expiry_days', 30))
        
        # Generate UUID
        new_uuid = str(uuid_lib.uuid4())
        expiry_date = datetime.utcnow() + timedelta(days=expiry_days)
        
        # Create database record
        user = VMessUser(
            name=name,
            uuid=new_uuid,
            data_limit_gb=data_limit,
            expiry_date=expiry_date
        )
        
        try:
            db.session.add(user)
            db.session.commit()
            
            # Add to Xray config
            run_command(f'/opt/ssh-panel/scripts/manage_vmess.sh add {new_uuid}')
            
            flash(f'VMess user "{name}" created successfully!', 'success')
            return redirect(url_for('vmess_list'))
        except Exception as e:
            db.session.rollback()
            flash(f'Error creating user: {str(e)}', 'danger')
    
    return render_template('vmess_create.html')

@app.route('/vmess/<int:user_id>/delete', methods=['POST'])
@login_required
def vmess_delete(user_id):
    """Delete VMess user"""
    from models import VMessUser
    
    user = VMessUser.query.get_or_404(user_id)
    uuid = user.uuid
    name = user.name
    
    try:
        # Remove from Xray config
        run_command(f'/opt/ssh-panel/scripts/manage_vmess.sh remove {uuid}')
        
        # Delete from database
        db.session.delete(user)
        db.session.commit()
        
        flash(f'VMess user "{name}" deleted successfully!', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'Error deleting user: {str(e)}', 'danger')
    
    return redirect(url_for('vmess_list'))

@app.route('/vmess/<int:user_id>/link')
@login_required
def vmess_link(user_id):
    """Get VMess link"""
    from models import VMessUser, ServerConfig
    
    user = VMessUser.query.get_or_404(user_id)
    
    # Get configs
    address_config = ServerConfig.query.filter_by(key='vmess_address').first()
    address = address_config.value if address_config else 'ssh.thunnwathanlin.codes'
    
    host_config = ServerConfig.query.filter_by(key='vmess_host').first()
    host = host_config.value if host_config else ''
    
    port_config = ServerConfig.query.filter_by(key='vmess_port').first()
    port = port_config.value if port_config else '443'
    
    tls_config = ServerConfig.query.filter_by(key='vmess_tls').first()
    tls = tls_config.value if tls_config else 'tls'
    
    # Generate link
    cmd = f'/opt/ssh-panel/scripts/generate_vmess_link.py {user.uuid} {address} {port} /ws "{host}" {tls} "{user.name}"'
    success, output, error = run_command(cmd)
    
    if success:
        return jsonify({'link': output.strip()})
    else:
        return jsonify({'error': error}), 500

@app.route('/vmess/<int:user_id>/qr')
@login_required
def vmess_qr(user_id):
    """Generate QR code for VMess link"""
    from models import VMessUser, ServerConfig
    import qrcode
    from io import BytesIO
    
    user = VMessUser.query.get_or_404(user_id)
    
    # Get configs
    address_config = ServerConfig.query.filter_by(key='vmess_address').first()
    address = address_config.value if address_config else 'ssh.thunnwathanlin.codes'
    
    host_config = ServerConfig.query.filter_by(key='vmess_host').first()
    host = host_config.value if host_config else ''
    
    port_config = ServerConfig.query.filter_by(key='vmess_port').first()
    port = port_config.value if port_config else '443'
    
    tls_config = ServerConfig.query.filter_by(key='vmess_tls').first()
    tls = tls_config.value if tls_config else 'tls'
    
    # Generate link
    cmd = f'/opt/ssh-panel/scripts/generate_vmess_link.py {user.uuid} {address} {port} /ws "{host}" {tls} "{user.name}"'
    success, output, error = run_command(cmd)
    
    if not success:
        return "Error generating link", 500
    
    # Generate QR code
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(output.strip())
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convert to bytes
    img_io = BytesIO()
    img.save(img_io, 'PNG')
    img_io.seek(0)
    
    return send_file(img_io, mimetype='image/png')

@app.route('/vmess/<int:user_id>/toggle', methods=['POST'])
@login_required
def vmess_toggle(user_id):
    """Toggle VMess user active status"""
    from models import VMessUser
    
    user = VMessUser.query.get_or_404(user_id)
    user.is_active = not user.is_active
    
    try:
        db.session.commit()
        
        if user.is_active:
            run_command(f'/opt/ssh-panel/scripts/manage_vmess.sh add {user.uuid}')
        else:
            run_command(f'/opt/ssh-panel/scripts/manage_vmess.sh remove {user.uuid}')
        
        flash(f'User "{user.name}" {"enabled" if user.is_active else "disabled"}!', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'Error: {str(e)}', 'danger')
    
    return redirect(url_for('vmess_list'))

@app.route('/vmess/settings', methods=['GET', 'POST'])
@login_required
def vmess_settings():
    """VMess settings configuration"""
    from models import ServerConfig
    
    if request.method == 'POST':
        address = request.form.get('address')
        host = request.form.get('host')
        port = request.form.get('port')
        tls = request.form.get('tls')
        
        # Update configs
        configs = {
            'vmess_address': address,
            'vmess_host': host,
            'vmess_port': port,
            'vmess_tls': tls
        }
        
        for key, value in configs.items():
            config = ServerConfig.query.filter_by(key=key).first()
            if config:
                config.value = value
            else:
                config = ServerConfig(key=key, value=value)
                db.session.add(config)
        
        db.session.commit()
        flash('VMess settings updated successfully!', 'success')
        return redirect(url_for('vmess_settings'))
    
    # Get current settings
    address_config = ServerConfig.query.filter_by(key='vmess_address').first()
    current_address = address_config.value if address_config else 'ssh.thunnwathanlin.codes'
    
    host_config = ServerConfig.query.filter_by(key='vmess_host').first()
    current_host = host_config.value if host_config else ''
    
    port_config = ServerConfig.query.filter_by(key='vmess_port').first()
    current_port = port_config.value if port_config else '443'
    
    tls_config = ServerConfig.query.filter_by(key='vmess_tls').first()
    current_tls = tls_config.value if tls_config else 'tls'
    
    return render_template('vmess_settings.html', 
                         address=current_address, 
                         host=current_host,
                         port=current_port,
                         tls=current_tls)

# ============================================================================
# OUTLINE VPN ROUTES
# ============================================================================

@app.route('/outline', methods=['GET', 'POST'])
@login_required
def outline_users():
    """Outline users page (create + list in one page)"""
    from models import OutlineUser, ServerConfig
    import secrets
    import base64
    import urllib.parse
    
    if request.method == 'POST':
        name = request.form.get('name')
        data_limit = float(request.form.get('data_limit', 0))
        
        # Generate random password and port
        password = secrets.token_urlsafe(16)
        port = 8388 + OutlineUser.query.count()
        method = 'chacha20-ietf-poly1305'
        
        # Get server address
        address_config = ServerConfig.query.filter_by(key='outline_address').first()
        server_address = address_config.value if address_config else '167.172.67.17'
        
        # Generate Shadowsocks access key with name
        credentials = f"{method}:{password}"
        encoded = base64.urlsafe_b64encode(credentials.encode()).decode().rstrip('=')
        name_encoded = urllib.parse.quote(name)
        access_key = f"ss://{encoded}@{server_address}:{port}#{name_encoded}"
        
        # Create user
        user = OutlineUser(
            name=name,
            access_key=access_key,
            password=password,
            port=port,
            method=method,
            data_limit_gb=data_limit
        )
        db.session.add(user)
        db.session.commit()
        
        # Auto-start Shadowsocks server
        try:
            result = subprocess.run(
                ['/opt/ssh-panel/scripts/start_outline_server.sh', name, user.password, str(user.port)],
                capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0:
                flash(f'Outline user {name} created and server started!', 'success')
            else:
                flash(f'User created but server failed to start. Please start manually.', 'warning')
        except Exception as e:
            flash(f'User created but auto-start failed: {str(e)}', 'warning')
        return redirect(url_for('outline_users'))
    
    # Get all users
    users = OutlineUser.query.order_by(OutlineUser.created_at.desc()).all()
    
    # Get server address for display
    address_config = ServerConfig.query.filter_by(key='outline_address').first()
    server_address = address_config.value if address_config else '167.172.67.17'
    
    return render_template('outline_users.html', users=users, server_address=server_address)

@app.route('/outline/<int:user_id>/delete', methods=['POST'])
@login_required
def outline_delete(user_id):
    """Delete Outline user"""
    from models import OutlineUser
    
    user = OutlineUser.query.get_or_404(user_id)
    name = user.name
    db.session.delete(user)
    db.session.commit()
    
    flash(f'Outline user {name} deleted successfully!', 'success')
    return redirect(url_for('outline_users'))

@app.route('/outline/<int:user_id>/toggle', methods=['POST'])
@login_required
def outline_toggle(user_id):
    """Toggle Outline user active status"""
    from models import OutlineUser
    
    user = OutlineUser.query.get_or_404(user_id)
    user.is_active = not user.is_active
    db.session.commit()
    
    status = 'enabled' if user.is_active else 'disabled'
    flash(f'Outline user {user.name} {status}!', 'success')
    return redirect(url_for('outline_users'))

@app.route('/outline/<int:user_id>/key')
@login_required
def outline_key(user_id):
    """Get Outline access key"""
    from models import OutlineUser
    
    user = OutlineUser.query.get_or_404(user_id)
    return jsonify({'key': user.access_key})

@app.route('/outline/<int:user_id>/qr')
@login_required
def outline_qr(user_id):
    """Generate QR code for Outline access key"""
    from models import OutlineUser
    import qrcode
    from io import BytesIO
    
    user = OutlineUser.query.get_or_404(user_id)
    
    # Generate QR code
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(user.access_key)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convert to bytes
    buf = BytesIO()
    img.save(buf, format='PNG')
    buf.seek(0)
    
    return send_file(buf, mimetype='image/png', as_attachment=False, download_name=f'{user.name}_outline_qr.png')

@app.route('/outline/settings', methods=['GET', 'POST'])
@login_required
def outline_settings():
    """Outline server settings"""
    from models import ServerConfig
    
    if request.method == 'POST':
        address = request.form.get('address')
        
        # Update address
        address_config = ServerConfig.query.filter_by(key='outline_address').first()
        if address_config:
            address_config.value = address
        else:
            address_config = ServerConfig(key='outline_address', value=address)
            db.session.add(address_config)
        
        db.session.commit()
        flash('Outline settings updated successfully!', 'success')
        return redirect(url_for('outline_settings'))
    
    # Get current settings
    address_config = ServerConfig.query.filter_by(key='outline_address').first()
    current_address = address_config.value if address_config else '167.172.67.17'
    
    return render_template('outline_settings.html', address=current_address)

