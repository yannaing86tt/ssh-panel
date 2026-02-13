# GitHub Upload Guide

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `ssh-panel`
3. Description: `Complete SSH/VMess/Outline VPN management panel with auto-installer`
4. Visibility: **Public** (recommended) or Private
5. Initialize: **Do NOT** check any boxes (README, .gitignore, license)
6. Click **Create repository**

## Step 2: Upload Files

### Option A: Web Upload (Easiest)

1. Click **uploading an existing file**
2. Drag and drop ALL files from `/tmp/ssh-panel-installer/`:
   - deploy.sh
   - README.md
   - QUICKSTART.md
   - CHANGELOG.md
   - LICENSE
   - .gitignore
   - app.py
   - models.py
   - requirements.txt
   - scripts/ (entire folder)
   - templates/ (entire folder)
3. Commit message: `Initial release - Complete SSH/VMess/Outline panel`
4. Click **Commit changes**

### Option B: Git Command Line

```bash
cd /tmp/ssh-panel-installer

# Initialize repo
git init
git add .
git commit -m "Initial release - Complete SSH/VMess/Outline panel"

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/ssh-panel.git

# Push
git branch -M main
git push -u origin main
```

## Step 3: Update README Links

After upload, edit `README.md` and `QUICKSTART.md`:

**Replace:**
```
https://raw.githubusercontent.com/YOUR_USERNAME/ssh-panel/main/deploy.sh
```

**With:**
```
https://raw.githubusercontent.com/your-actual-username/ssh-panel/main/deploy.sh
```

## Step 4: Test Installation

On a fresh VPS:

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/ssh-panel/main/deploy.sh | sudo bash
```

Or:

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/ssh-panel/main/deploy.sh
chmod +x deploy.sh
sudo bash deploy.sh
```

## Step 5: Add Release Tag (Optional)

```bash
git tag -a v2.0.0 -m "Production release with all features"
git push origin v2.0.0
```

## Example Repository Structure

```
your-username/ssh-panel/
├── README.md                    # Main documentation
├── QUICKSTART.md               # Quick start guide
├── CHANGELOG.md                # Version history
├── LICENSE                     # MIT license
├── .gitignore                  # Git ignore rules
├── deploy.sh                   # One-command installer ⭐
├── install.sh                  # Alternative installer
├── app.py                      # Flask application
├── models.py                   # Database models
├── requirements.txt            # Python dependencies
├── scripts/                    # Helper scripts
│   ├── manage_ssh_user.sh
│   ├── generate_ssh_config.sh
│   ├── generate_qr.py
│   ├── start_outline_server.sh
│   ├── delete_outline_server.sh
│   ├── generate_outline_key.py
│   ├── generate_vmess_link.py
│   └── manage_vmess.sh
└── templates/                  # HTML templates
    ├── base.html
    ├── login.html
    ├── index.html
    ├── users.html
    ├── create_user.html
    ├── banner.html
    ├── vmess_list.html
    ├── vmess_create.html
    ├── vmess_settings.html
    ├── outline_users.html
    └── outline_settings.html
```

## One-Liner Installation (After Upload)

Users can install with:

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/ssh-panel/main/deploy.sh | sudo bash
```

This will:
1. Prompt for domain
2. Install all dependencies
3. Configure everything automatically
4. Show credentials at the end

## Troubleshooting

### Permission denied on scripts
Add execute permission:
```bash
chmod +x deploy.sh
```

### 404 not found
- Check repository is public
- Check file path is correct
- Wait 1-2 minutes for GitHub cache

### Installation fails
Check:
- DNS pointing to server IP
- Server has internet access
- Running as root (sudo)
- Ubuntu 20.04+ or Debian 11+

## Share Your Repo

After upload, share this link:

```
https://github.com/YOUR_USERNAME/ssh-panel
```

Users can clone with:

```bash
git clone https://github.com/YOUR_USERNAME/ssh-panel.git
cd ssh-panel
sudo bash deploy.sh
```
