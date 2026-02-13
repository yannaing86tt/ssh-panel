from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()

class Admin(UserMixin, db.Model):
    """Admin user model"""
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class SSHUser(db.Model):
    """SSH user account model"""
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    expiry_date = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    max_connections = db.Column(db.Integer, default=2)
    is_active = db.Column(db.Boolean, default=True)
    notes = db.Column(db.Text, nullable=True)
    
    def is_expired(self):
        return datetime.utcnow() > self.expiry_date
    
    def days_remaining(self):
        delta = self.expiry_date - datetime.utcnow()
        return max(0, delta.days)

class Connection(db.Model):
    """Active SSH connection tracking"""
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), nullable=False)
    ip_address = db.Column(db.String(45), nullable=False)
    connected_at = db.Column(db.DateTime, default=datetime.utcnow)
    upload_bytes = db.Column(db.BigInteger, default=0)
    download_bytes = db.Column(db.BigInteger, default=0)

class ServerConfig(db.Model):
    """Server configuration for SlowDNS, etc."""
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(100), unique=True, nullable=False)
    value = db.Column(db.Text, nullable=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class VMessUser(db.Model):
    """VMess User Model"""
    __tablename__ = 'vmess_users'
    
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False, unique=True)
    uuid = db.Column(db.String(36), nullable=False, unique=True)
    data_limit_gb = db.Column(db.Integer, default=0)  # 0 = unlimited
    used_data_gb = db.Column(db.Float, default=0.0)
    expiry_date = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_active = db.Column(db.Boolean, default=True)
    
    def __repr__(self):
        return f'<VMessUser {self.name}>'
    
    def is_expired(self):
        return datetime.utcnow() > self.expiry_date
    
    def is_data_exceeded(self):
        if self.data_limit_gb == 0:
            return False
        return self.used_data_gb >= self.data_limit_gb
    
    def get_status(self):
        if not self.is_active:
            return 'Disabled'
        if self.is_expired():
            return 'Expired'
        if self.is_data_exceeded():
            return 'Data Limit Exceeded'
        return 'Active'
    
    def days_remaining(self):
        delta = self.expiry_date - datetime.utcnow()
        return max(0, delta.days)

class OutlineUser(db.Model):
    """Outline VPN user model"""
    __tablename__ = 'outline_users'
    
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    access_key = db.Column(db.String(500), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)  # Shadowsocks password
    port = db.Column(db.Integer, nullable=False)
    method = db.Column(db.String(50), default='chacha20-ietf-poly1305')
    data_limit_gb = db.Column(db.Float, default=0)  # 0 = unlimited
    used_data_gb = db.Column(db.Float, default=0)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def get_status(self):
        """Get user status"""
        if not self.is_active:
            return 'Disabled'
        if self.data_limit_gb > 0 and self.used_data_gb >= self.data_limit_gb:
            return 'Quota Exceeded'
        return 'Active'
    
    def remaining_data_gb(self):
        """Get remaining data in GB"""
        if self.data_limit_gb == 0:
            return float('inf')
        return max(0, self.data_limit_gb - self.used_data_gb)
