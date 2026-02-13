#!/bin/bash
# SSH Panel Auto-Deploy Script
# This script contains all application files and auto-installs everything

set -e

echo "â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
echo "â•‘   SSH Panel Auto-Deployment v2.0           â•‘"
echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root: sudo bash deploy.sh"
    exit 1
fi

# Prompt for domain
read -p "Enter domain name (e.g., ssh.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "Domain is required!"
    exit 1
fi

echo "Installing SSH Panel for: $DOMAIN"
echo ""

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || echo "Unknown")
echo "Server IP: $SERVER_IP"
echo ""
echo "Make sure DNS is pointing $DOMAIN â†’ $SERVER_IP"
read -p "Press Enter to continue..."
echo ""

# Install system packages
echo "[1/15] Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt update -qq > /dev/null 2>&1
apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx \
    git net-tools psmisc shadowsocks-libev curl ufw -qq > /dev/null 2>&1

# Create directory
echo "[2/15] Creating directory structure..."
mkdir -p /opt/ssh-panel/{scripts,templates,static,instance}
cd /opt/ssh-panel

# Generate credentials
echo "[3/15] Generating admin credentials..."
ADMIN_USER="admin_$(openssl rand -hex 3)"
ADMIN_PASS=$(openssl rand -base64 18)
SECRET_KEY=$(openssl rand -hex 32)

cat > .env << ENV
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
SECRET_KEY=$SECRET_KEY
ENV

chmod 600 .env

# Create requirements.txt
cat > requirements.txt << 'EOF_REQ'
Flask==3.0.0
Flask-SQLAlchemy==3.1.1
Flask-Login==0.6.3
Werkzeug==3.0.1
qrcode[pil]==7.4.2
Pillow==10.2.0
python-dotenv==1.0.0
gunicorn==21.2.0
psutil==5.9.8
EOF_REQ

# Install Python deps
echo "[4/15] Installing Python dependencies..."
python3 -m venv venv > /dev/null 2>&1
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt

echo "[5/15] Extracting application files..."
# Application files will be appended to this script
# Extract from DATA section at end of script
ARCHIVE_LINE=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0; }' "$0")
tail -n +${ARCHIVE_LINE} "$0" | tar xz -C /opt/ssh-panel

# Install Xray
echo "[6/15] Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.8.16 > /dev/null 2>&1

mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << 'XRAYCONF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 10000,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {"clients": []},
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "/ws"}
    }
  }],
  "outbounds": [{"protocol": "freedom", "settings": {}}]
}
XRAYCONF

systemctl enable xray > /dev/null 2>&1
systemctl start xray

# Initialize database
echo "[7/15] Initializing database..."
cd /opt/ssh-panel
cat > init_db.py << 'INITDB'
from app import app, db
from models import Admin
from werkzeug.security import generate_password_hash
import os
from dotenv import load_dotenv

load_dotenv()

with app.app_context():
    db.create_all()
    admin = Admin(
        username=os.getenv('ADMIN_USERNAME'),
        password_hash=generate_password_hash(os.getenv('ADMIN_PASSWORD'))
    )
    db.session.add(admin)
    db.session.commit()
    print("Database initialized successfully")
INITDB

venv/bin/python3 init_db.py
rm init_db.py

# Create systemd service
echo "[8/15] Creating systemd service..."
cat > /etc/systemd/system/ssh-panel.service << SERVICE
[Unit]
Description=SSH Panel
After=network.target

[Service]
Type=notify
User=root
WorkingDirectory=/opt/ssh-panel
Environment="PATH=/opt/ssh-panel/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/ssh-panel/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ssh-panel > /dev/null 2>&1

# Configure Nginx
echo "[9/15] Configuring Nginx..."
cat > /etc/nginx/sites-available/ssh-panel << NGINXCONF
server {
    listen 80;
    server_name $DOMAIN;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/ssh-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1
systemctl reload nginx

# Install SSL
echo "[10/15] Installing SSL certificate..."
echo "This may take a moment..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos \
    --email admin@$DOMAIN --redirect --quiet || {
    echo "Warning: SSL installation failed. You can run certbot manually later."
}

# Configure firewall
echo "[11/15] Configuring firewall..."
ufw --force enable > /dev/null 2>&1
ufw allow 22/tcp > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw allow 8388:8395/tcp > /dev/null 2>&1
ufw allow 8388:8395/udp > /dev/null 2>&1

# Make scripts executable
echo "[12/15] Setting script permissions..."
chmod +x /opt/ssh-panel/scripts/*.sh
chmod +x /opt/ssh-panel/scripts/*.py

# Update database configs
echo "[13/15] Configuring default settings..."
venv/bin/python3 << PYCONF
from app import app, db
from models import ServerConfig

with app.app_context():
    configs = [
        ('ssh_banner', 'Welcome to SSH Server'),
        ('vmess_address', '$SERVER_IP'),
        ('vmess_port', '443'),
        ('vmess_tls', 'tls'),
        ('vmess_host', '$DOMAIN'),
        ('outline_address', '$SERVER_IP')
    ]
    
    for key, value in configs:
        config = ServerConfig.query.filter_by(key=key).first()
        if not config:
            config = ServerConfig(key=key, value=value)
            db.session.add(config)
    
    db.session.commit()
PYCONF

# Start services
echo "[14/15] Starting services..."
systemctl start ssh-panel
sleep 3

# Verify
echo "[15/15] Verifying installation..."
PANEL_STATUS=$(systemctl is-active ssh-panel 2>/dev/null || echo "inactive")
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
XRAY_STATUS=$(systemctl is-active xray 2>/dev/null || echo "inactive")

echo ""
echo "â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
echo "â•‘       Installation Complete! âœ…            â•‘"
echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo ""
echo "Panel URL:      https://$DOMAIN"
echo "Admin Username: $ADMIN_USER"
echo "Admin Password: $ADMIN_PASS"
echo "Server IP:      $SERVER_IP"
echo ""
echo "Services Status:"
echo "  Panel:  $PANEL_STATUS"
echo "  Nginx:  $NGINX_STATUS"
echo "  Xray:   $XRAY_STATUS"
echo ""
echo "Credentials saved to: /root/panel-credentials.txt"
echo ""

# Save credentials
cat > /root/panel-credentials.txt << CREDS
SSH Panel Installation
======================
Panel URL: https://$DOMAIN
Admin Username: $ADMIN_USER
Admin Password: $ADMIN_PASS
Server IP: $SERVER_IP
Installation Date: $(date)

Services:
- Panel: $PANEL_STATUS
- Nginx: $NGINX_STATUS
- Xray: $XRAY_STATUS
CREDS

echo "Next Steps:"
echo "1. Access panel: https://$DOMAIN"
echo "2. Login with credentials above"
echo "3. Create SSH/VMess/Outline users"
echo ""
echo "Documentation: /opt/ssh-panel/README.md"
echo ""

exit 0

__ARCHIVE_BELOW__
‹      ì}ërãÆÒØùÍ§cwÉc‘"©›Ãkµ²êx/–´>ŸKVø(Â ¥å‘õ3¿“TòUª¾Jªòyžóy…t÷Ì ƒ+/º­í…½".3=====Ý==3ºç5½ÙŸôjÁµ½¹I¿p¥~·7¶Ú›jÃŸVg«µó§V»µÓÙøk=,Züš¡î3ö'ßuÃ²tó¾ÿF¯‘ïNØÈÖƒKfM<×Ù7ø°Æ|Ó1L¿šÏÖC_ü25ƒoË7‡p7õíþÈõ×Àxý¸Ž5š­± 2÷G–mVbø}Û½°YÊwøðFwôòÓ§þ4÷î4ŒàEkl8õ1þ•Ãž¸†i¬1XcûÆÄrÖØÉÉ_?Œ×q ]ËÅ—¦eúðfd]ðüT.´&fA<¯1ü°C]$tCÓ¹’ÉlW7úüUE¼ryLžïÍ zõ€Š\ÈG/˜†–-Ÿ~ñ‡P	^ŠåÊ^ÍB38z'!m+•g@8Ý`Pªå»ÎHÁ®tßÒ¶TœjõJE÷<ÖãÍYë÷}böûu|ÛRýÏª'‡Ç‡§ý¿þX=‡¤nÐ¼0)·úeUs¤Oí°˜Cß—æ¬1ëÎ…ÙÇVPMýþ»ýïþzøæÇþëýÓýWû'‡ýÇGTB5øÅ¶B³»—ë…ëA0nxºcÚë–ýÐšøªO¯šÆ Zøôxÿàoý7ï^}st°zôîí	ÁÿF·³R1MË±Â>ä®Á¿:ÒèÐ ¶ö§^…óÖ„ó dVYè—øœ‚—üÆŸ®,ó«HOÕJåëd"äØ>¶0.Ð“3¾¬ÑË¨w+. ðÔw87¡Çù3l”šå„QBªÏ_MÛ´GS‡X;  þÔéÝ	”iÔÄ¯ «iÚáGs8MŒMÛfâ3Ã¢LèvÞ4„””#ôg<+Ç* €êÅ¬Ý„Âd!khïÔŸBÇêÀ3ûžxš£[èXð­·Ñª+
¼œ&Â^Áz=ÖZ“ïƒÐ€Œê£éûÃü84½ÒÐƒé3»iðÄk@@8ôk&PÉî³ d]ßrFn-¦Ù·&ôf’Œ'`˜ÀŸèX†¤ÔÐ›ö¡-†Ø{¢o7•—Øx C·{m^á‰9qýYœ:s8Õí>_ã‰dr”Ÿ€]€•jÕõ*O¡òËMTÕ*”\íªH­Åßx	Èw¤áOÍÂd¡êvœŽÙ:«µ[Í¿üe£¾ÆØ3öí«8ŸÀ’€ã}hJ"SšXêmÜ@:ðù•	ì-¥yj'Û
@OˆòŸ)‰ecÓ!rïšàö5Ö"«ýF»»ìWvá›k\±jÎªð|=d[ã„·FL†Ã°ŸrÈÀ¾åÕêuµ™Zq}¨7ÇöAþ…é*f¨Ã(jÔ‰fÁP'6Ì+khÂç)°aíýÑëÆ@‡–@<y]’@Œ(¾©>Å»NàÅFˆv@©›Ûø´à¨ƒ0Iáµ ¡¡¨Fèx’ØÕn§S•‡'0tD_`P0ªšÂõqPÝyqc@vp`P—RM¶F3ð`ªUrªõ8½ é¸!ÏÙy™ô
€àÛdrêø®ZÎÔÌ|H¼xR)ô¡4
£QItkH‚±¡­y–Ñkw66×FFo³^Oä†o0†„Ã1RÏl¦îÇ5¿Šyj?_Öa€Fìêy•‰2¯Š; @$Á4/|wêÕÚÉÂRµE¦¬„Ò’….YÐJXkTCéÃLTl q<iFšìâ±@æ–5\¦ûAy&söZepêÔ3€¨bé!*[ª†äýˆq“™›ôeºŒX¤ÑŽy¾uu®!‹¦>}í…ÁzKË…G}8ÄOÁ_j?]+Eçã$ˆAå×YGØö”äùÌ“¬õÉ¥å14µ¨[OKÇ½v
Ól¨$è¤gUÌ‰
«ÈX=/F¯Â> ¯LeŸöal¥êè=ïÙ±¤^YŒº—Ûµ³Vã?4Ï¿¬w©oÿ|ÉEEn'O‘B‚,¯3Ç·o¡m sÌo™Rbˆò£¦237Ê1Â+N{&Á >SÅwÓ T…ªë ¸9‚#¾E¾V¿-…žù,qÞÔ£Ñ$I€9:¥¼ÐFAû”|ÐF]DÕ!þ²áØ^‚ÕGrŸäV—Ý˜·Z–Ì	Fcë«©e(8A9â£/Žj8ÚKP*xê£ÁDo€^Âæv|â… ¤ÇpGÚ´UP\ÅT?nf$xª5¹R~²}3”ÈiðlÞz}Ru ¥m:µ9Íœ$yÌ1&Ø÷êh´ ®­D„n¨”\Aï	°ê¿Fþòñžkþ_'}"¤OÂèj~TtÇ×z0¸ºoDÆêØlB¨	FJv~Â‘eƒÓÌjV Ôq4ë	æGñ*…Q“/)ñ¬N¶ù^šÓpòtç<äT¸Whp46êDÒ„™—±¢RN¯Z•Û‡;§m£K¡nO¹/É¡Ò¹§>”äI¶—xš_’B›^öUI~N°žB70š<Ék`%†c×zgÕoOQN¿wrŠ]»; ‘Â¡äßào#³d”pï5‘É¦áž­!4†‘±µ¤#²&ü¢¹ªõ¤¡ —MŽjk³\1'£‘OŽ—ªüXeˆ§Áµë¹éåG%}t£S­{	ïNÜ«dI=yS‡~*:"T‡Ã ×A¡Q¦/K­É›”u{Xk”-)#(1aV`¢ï·V=r®tÛŠ•|TP#R 3ÐÐ˜ã¸Èt9Â”w¹Nƒ»È?*,ö½Ü¥¸•kõJi¥9C×Ó¥SO+(œ¾©e£/BZÆ\^[áXUIÐKìpüÍ˜@>ÎòõÐ7±7ôõ°i˜Á…d<Ð'lõ/Ci"Bè1!¢$~kJ½ø6M+PÌ@¡¹Ö:í—I‡<rò\
=¹[–¨ùŠ¾IÂñ”}î#Fâ)þL»4g=´xú«dÿZ\^ˆBÑjÌÊ÷j¢ï&°Mv£Ä§&ô¥)Š#RI,#B¦ÒkŒ€÷ÐIa`À	àRŽÀsdš’=;–*®¢›glßóì™À=|@‰Pïp=ÐäªëáÄ[n†É¦»®ÖQ¥¤OóÚ·€årk£2c;Ä‚§iP€À&VTçÔÐc9ˆ°u3â»õø¢Ï'Ý[¦Á¨‰¿þ§gœiÁ2rÌ_Å}¤_«ñ[4ÌÑ(€ÃlþåSûCí¡ŽÂ`¬åÐVÈÿ¸k

ÒC7šÚöìlBñBé…2XöÐTRA|ÔËí6éŽF=†U«¥BOJH½d9½äcîÀ°Îåò²’ŽçÃR$îè-sÌëh Q´¤§Wh}†:»³éñ#T{£¥4ÞDÿH£Pa&™@(¤¿£dwÀ<r‘£/Hä<uë;@åHZ©0Ê]hÒ0<ª`.2tŠU²<%hTE ìF&¾M•øEZšÛöÈôQCÎ*bvŠæÅåÇátTMMµ$
%ÃFf¢‚ùlv¸Å½­ÆZlìð ;jTåS‹0àwÙ”z«T/šsw|Ò.5 ™ê%ði¾¯+õnÄÍ­oè÷VÂ§ð{›ÇÂ;ž™ÃI.¼9U1vŒh*j˜…¬²À7|ÆFša¦i”Ì÷Ï	?˜¾5š©Å±k0ÁÚ›‚ú6èQŽ+JßH<»ys5£*¨ö1w$µ¤eØ|’*H*L‡F`ñƒm3‚ÈQyðE­U02-Ð'´âñ‡¦!O¿ÿŽ˜åY7¢ŽEÌS9—5AQ2ˆy`Õq/VûWI/ë*a_Æ+5ì°=ü£ˆPóš°ŒZ¢æI—ô	HiÐ“7ÉÏ
r=å>™(%ã{ò9™Š$zþFï•‘'©œÊZå&(VG‹Äµè"wÒ\„™¸€¥«ðT¾½Ë‹]1»"öcoØL©eúOžh‚nBú˜Q1’l¡ô]¿¿ÙÚŒàÄ5|Æ¨ô0””!‘À135Óò&Y–ßŠ»‰Òöf-æ"¾¨äóC\¶ á\¦˜Ïó¬`’…—'/hÜCúÈ“wI+5òRú^¾™Y™W%kõÖâ4æÌ„âBØ¯Ø`)¢gžÕ¸ŽÒˆ’×Vâ«¢ä›ºÝ ÐCÅ+$’*E%ÜÝq0cf’§HÌ‘i£H`å>Ížºg­óÞÜ OAµ ™ô©§Xöß1ÀÅsmh²É*,ÄDÂ&Ð1¤µŒ³>AÕb(Æ/?d(ƒžˆ±É‰zÆÞë>š×c·EÎñÙ|J°RP‘0¦“í{vžðE=@K~(‹>–_EöÜ œk£´u¶×c[ù3»J•šÐd@åZvúL^±=ÚåXœµÎ‹ç#ª–¥Û<®ÖêÕzIä9œ¦cÕæÏÐÜ¼gîæy¶ŽxÝfoÉ–%=†;Öw'°„dµö
8óÂtLÇž/25Õ0žB†W¡+ƒªKEø|ÛUJx1EF¾B eûØ…?‚‡ºÕ:4HLŽ‡ô}Ž —g„ßþGžq¯ãÔ']¼òŒ}…w=«‚Š«‘âu3²6áw_¢­$q£ ÔwY§SÁØDdVeHA~ak×ª/~l¼˜4^Õú-N¦¾.D4x‡ìV‚„¹ûµZF×žž¾gGÎÏÐÔÐËÞë3×íVâÝÚ*€. )ÛHå!…tk¬Ój­±›*Æ«°q:óˆEñã:nËyÉ†c”:aoŽ_•Í?
6—°^[ç6 €Uõ0Ô‡cIüCLWE:ÏÐÏz›âé_üåùù¿Œ—¿?f4…Ò+æë'eé_|dØØ¢»¾¾p;k* ÀCù›ßÀOÒ¡
Ók¯±û±Xÿ0{í>à¤No«.2¢)C(Ô*Ñ‡‰~iÖFNS§)&T%è[Œ2ÙÐ–¶ë÷´­/5(	~ä»ë±êŸd0±Î@Ð 7ýÊ¬ÁÇ5ÆC{Õ÷o¿J¼ÍÌ¼¬µ²22ZõÁ3O †ÀÖ½*á·î9háÀ "W#ë²ßŸ ·÷ûÂ}IÈ‚ð9;„êmÍPØM±æ!‚Wä«Ä„©ðSd]øvÎ|¬²0bÿõ›£·ý'‡Ço÷ß‚’˜ïLLô.(›Æ»™¼ï÷ONþþîøu:oÊDÎ™î-Õ®©ûOö˜^µÕ¤ÿ02äoo«…bË0Ó‹Ó×AXþðU>EGKRxä
kH_†N‹Ì*r)Ëtj8•ƒ¿}Ûä,›IJ¡«	×ÚóÄ}ëcìwzú•£EÊ¼/9+†(Õi¯Ê9ØèíÂZvŒGræ”þ¦UJ¼âŒ/ˆçÍŸ2ˆ+¾p½^
K Eæ!
ç Ró(ó€vÀ‰%V¦LR§¢á¿ÄDUÒ¤g&¹Q>½N:Î¦kF$Ó6ñf³–‡È¢:«R9&\@Æ!‚(+£†LúóHÞdýxˆuOV)ù)¦pÿbÐ‹Ÿòôå¸ê¢›LˆwJB%x©'^4'”3ÿâë3¡O$,ä„âë´úÔ»Ðˆ±I¨´¯?ñ Ýq·cÚ)Ú2EÂ´È%K—D0Îü U…’¾kÛ¨¤h)Ñ1«äEw.âé
\&EÓ®ø[(„GQùžM. ïäÙä…(~¾<×æ
¢PÕCÓÃ@‘LÈîŠ‚{z©ÎFA³•L‡xÆŽÍ‰{%ü™y<¼ÿúèMš}•rý¨)ÆÉøRSßçûÙóºÆ‚nÕ9<^ÎßIÞ¦—æíò®8Ÿ­mË¹œ£»8—YÆU4œlø}îM­n^•—…ÇËç|(BÍÃ§^½x¤¯žÈ˜
¶oNpÂ‘*Çp ß7ÃñÔq®õp¬c€x® £ŽzëòXb®Šø
 (ðbäÔBÔèúƒÍ²<˜+…µoO…c Â1ØÜÜPíÚ
2¥P€7?# ÀËÇÌIê20÷•$D„¸_€Ù =ü(ÇØà
ŒO Ü²õë D
6ˆ”@á#‘{«qŒ2þYšû-ŠAúmÑOé¼©Rßî¦¼¯Â{˜ÓËdå³Ï]ŽÉm}iµ€4ù¥h~Óì—œ‰ \×ËEKrï‚@vÿ‚Ïrè³ú,‡î"‡rc•„@KÍÊ¨ÜPŸæâ$BÐë{qYæ­vhÏå3œf T) w0“¡" »o¹Å>Mþý+‘?“¿ZÀ¥)óx5ç
îÐ½¸°—µnx¦¬H?¥÷Šu#'/ù’´‡µu±6‡—Ø#öL¾,°t2D¬f,iÏ®nËÇ½W±†²±ôw3¶òÊÈX#¸¤Hv£™nâchYp±¦VÀSÜ>¨•ô€v‘\²šÇSæV|žœÿå¡&ˆ©Ç’>o&-äÐŒÕ…¬“1R0¢ÔbäÎ&å£|”NŒ¯9¡×4ÇŽ4;¿d.ó,ü|­ƒª?á%ž3«ZSšRWVw-/Õ¡KuÌýN¸w©n¹ßé.V)úx›Óe`l½@¬YÁH{F„IžvY\Ñ€ÙÕu‚ò–çÄÐ£µ9ô›H”•&…HI$äjú›FHyJWZ„#h¤:Ë},ÒHvÌDÌ£PÜùº‰¨Ô‡ÐàåÚŒß€&/Q}z^bò	hö••5ür/´d=9+—ébÑ%Ø£—b¨²,4Gª¶jIÍŸªt/[PnÇhÀ=møÖ»Çb>œ~wôöýðþ-;†‡Ã“û.#©ÀØ¿c©±_dã‹O•¡ÿ/&l=\Zë-¾ä;aT$ÀOõe@ *÷rðõ:Ë·7Õ7 q^ÐÃ %ÕŠ•æIG¶«/5Sª(‘9èƒž4‰€a !Ö&ÖMâ¥a‚
ÍÐ½4>T7ÐGf­½Qd¾Úøê+h…´9[Mà%)ÂªÃ±ÿwZËGÏµgíÖV5÷hO>ÑEÓêÙ2bI2Xþà‚—øYq|ioï4Û;&ýÔG†ùuÃ½Üá%®Ú¡¸O@‘GÄ$v]f0p[DæH»át¼íÆ‹¶âm LÚ¤Ê µ’È²MÑpýÁö&ÿVSà5Å«z½i˜ü®é‹(ËžÂ‰ÀƒVyèìB—§ð¬¸e¨>}¬³Â(+‘?ª’^•.÷ª<»Q‹Qê¤POL’G+ð­ÂÍÇ8öâÛ¥–ÁŒÏÊvÞ<=þ³Ø¤{”¨péË
ÓqÏØþ4t|9¯Êmœü±‘ž°/Úþ33‚YÌTf_v6^XÎ¹2…YPÔP²Îi¢<ñÈi™(¼èþní­DÖŒ¿iV»—Æ³: ±›är"ªBbL£$ ßˆHø$\\Ø&àŽ¢U‡TB“½·MŒám=ÑZØ¤…ôºïXäµŠŠœGPX¾s”²@2r d+´&C}Ž1‘ÜúJFje™hÇõSé®J!É…ìOÃ
@£œ­j»”0÷>¸”ªÄ	çÄ©­¥ðé%Ónînq§9‘jÿZLËx8³¬RäãÌÝ¸óê²<q×Åe™N³H-é‹–eÌñF'ª·¨?ú~ÚkQŸti3q\Q¾Øj‘/¶*}±Õ’öÝ»(tžãö~NÁô°)òcM$ò±âùà­–™Gôù~¦ÍX»]¬ê…ã²æOß‰+O‹/N¶h´z¨½T<é”Þ¬QXõ§¯™é‰MãAYvhÓ~²FU¥ƒ÷ckæÍJŽ]u$V›3S ’Y¥z)R|
³ŠÙ!æ!Å\ÏèJé•9úU/ƒZV/E69éÜÔ'^f™†
~5Ì÷èäO3ßºùË÷ŽŽþUuå´¹ÀM}þ©ÏòYåâ²áa€*?ÿ©Ýnµ:üü§í­<ÿ©½ÙÙú|þÓc\ÊùLÁ/¶nÇædß·Ïßžã„úÊë£å”Ÿ¦Ä¿^›þå?Ì)ŒÞ&ô+Œ
Š"®¤—§?¦¥’{›ÒK<Ý…I„u4Ä±Ø.ÂhEæäïô¶³¤rçG»ª¡’¸ötâÔàîÈ	M:›ÊóA5ðgäŒ¹¤/í„ËÖ¾j¡ßÊ±@Ì	¿“²m¹l$*V ©³µUÏÏ»4ÒY_ÃûSZ¸%Ö@öR«‘	ŽúEba`Ú ål#‹ši”ó[.Þ…6YPj¯ÚÂ¢ä‚éló×²X($'ÈŽ² ÷ºAížÖ«Bl°4¤Vœå³Àƒ°Nj+§BªI â4ÕDOdxåº¶©;q†˜Ärï¿DúSZCU-eÐ–èA_l‘M,“e®ì½=ÎâéUmH\¨Š9.WÆvI¥…}4K–„ÁÙ¢Ò¸ 9k´®@4ùz@ÁÉñ~/9Ì¼Ÿw*Ãs).•d„©ó¸ÊòÝ,/çf¡(ãØß…#§gd9f¸ËºÈp¤°#«n™ŒRÊ¨@Ž¨á&Y"*o{`»×¯ßž¬136Wn%>•–GfP¨;ÒôY¬c	Sb•Zc®Ã³g›N2^Äš¥#\¢‰‡7ª°î÷CÄQn% ãÊ¸ÃL±l—%l	ësÊ&‰™ tb9`„íE $fç
×˜ÖB‡µC™Ä&@	îÑÉò( š­§RV"ÑÜ¹ìùý~¬Uw#Ãme@B“ãf¯šó ƒ€¤&À96ÓÈÆuF Õä™¹FõÃ4V ÑÚ{½¨IÄhƒ-òKç DK@Q6/¸ú:áWë£²žŸ÷ÎÍš$Y€×¸iËws(’VÓ¤©ò12ÕÎO1’«ÑY!']7Ž•5O2¢.9;ðxÂN,šRƒ9ò²n-6ÍQ|s ÍÜ•Ð	ƒäñGùÈÃ 
@Ê¯E=:EJì´¬½q½ºÈ¼?«±X€ˆ)%âãäà½‰—$Á÷€œ<Èb!A˜_Ø÷Sºý’’$"²ÄZDéˆU08ñÛW)¢,3ðØ¿ªåŒ².\!‚rÀ5²ªÿ&½–Ÿ¯ûºd|ÖC–^Þ­­ÿ/¿'ÿïN«ÓÚÞBÿogsûOlë!‘’×Üÿ;'>ï^Ê˜ÓþíÎN'ÕþÛ­ögÿÿc\Ï¾XXÎú =ëïßŸöž·+rc¹ÞóNåÍáé_ßÁÝÍF·‘¯ÝV*'‡Ç?öq'»žÄÚYã9ÂÔ¢ß}	ø14´·¯!~×Ÿß¨@n›ÈÖÐÔpåCâˆI	Ÿ*CPaö˜ö\®±Ý]vøî›ÊÙÇ
Ï+¯MÎà ¡jÂ7SÃME!Y¯ìã‘=ÇA¼lW€‚S©œðâÎ+¸Eg/°&žmVP‹ï!KTðè‹ì<½õià1ƒ !¦ãèáÑÅTk\Â 0kLØsNâÊ1?f§§Û×`6@ÁG¼°íóÊßuPaW³Þ”2«Aq=¬*nˆJK\B •øôC7'®ÓðMôr)ïyŒ“B>¤»¦$à1éïb+U6Óí°«LG×™é^CR¬ßz8ô4ÖÁ0À«uT¹³)¦F*EÅŽ]¦ýóý÷œ¨d2Ë\‡ë÷‚§žºçü>®‚Í÷ZÆù¿±½#ÆÿíÍÍÎVäÿfg{ã³üŒK•ÿr'Oîj·óäçßT*û§GïÞâ$âèP9x÷ö›£o¥\Gh»CÝ&	ÿÑ×gbSì&ÆøðbHúsl '›0|/¿ä&–E[ûy3°Ý”øïDA(&“±¬JE9Pî¹‚%¿ø‰“ä¢øÌ×D)YÑ‚;Ädh[HÀ€ãc9<?¦‚n|q/J>«ŠW<xOåæ¯Îªžï†îÐµ«çZÅ÷4Uœn2]gs~VåÅÓ1ÕyÛ¨W-÷Œ~ŽÍ‘ÚºªcdÍ‘‘8rø6&ô ÆÔËR*%ÏÛ#âÓ‰'Ö ¯±Ñ;ìÐä^ÅóqçMh’ñé2BK«WxãÈ‚•¦>¦1‰Ú6ždVŽ£¯ÈEì×_Yö<ºj>9‚üçÄ¦„ŽŠÄ?¢iÄV÷Ë—I¼ø>õŽ´³ƒ´p›¾‡æGŠ`IBãi™p<K0Ý¦·†Xøœœ¸ÊþÙ÷œ}Ñ“Á:h6å¤ütÕø,Áª¸ÆUeÔèÄYeÛãGbÍûç;ÞL#íÓtÙž>QÎYõ[åŒJâFÞ]æ²dÒÍ&`‚Enx:Î²jœA“œ“nª¿ÔS­ÿ!€¡ø®EûHýÊ[ÿWlÑ[v†“‡çÊòÍVÈÚ*l3Ð‡÷¦ýfö¼R
ÜWTà<û³µ±ÿ?Çÿ=ÎúŸ4[MçJ
ŠhGv0D“ëÝóÖº'PWšÐ[/ÝäßK^ÆÀ_ù3öòwÅënbb‚ïóƒ(ÊW<gV;Ç«œ9«œc·þ3F«“_íŸno~æïáqmÎgh+±EË˜ãåËEË¢oG´Ì±š<A‹„'
?h&XþWu¶Ë¶ÓòRÊ•‚¾Ìvéø¶+I·a|Ã'ëž"à°D”Aµ¶B"1k(±9kŸ§çó¢OþIØòÊ‡suÊ.z½yžœ˜‹>l)'vpú¯Îr•˜h´Àå©{áÓ]ùKXî9|žÿg+íÿÝlw>Ûÿr-,ÿÅŠ¶‚Õl™€è. îeMÚ¼Sq„(]mÚ
Â·3WøRGb»ˆø\y*ŽJËS¾°.CVù/‚Óè˜z¾òLS%[êC~ûgú?žÂ)œ6÷åœ×ÿ7¶7Rýk»õ¹ÿ?Ê¥úÿäaDé9 ®õÞ÷ž×† Òà´†5LŠ€âÊG˜Û8?¾ûpÜrÿ‰{šdêt*4}#&kþŠû¡=—Åã«·¨e<`Ð{>a£À¢·ä±LP˜‹æ[h¾ä©IþI]å{ßOóüÿ[­MéÿßÞÞhSÿßÚùÜÿã*ÿÕµññVñÜé˜Ùf5ßD$ß’¢G$Uõè<‰(Új”ï¡´¹¹J|8îië×Û´Óž7¸5žàVLÕÂ8ŽOaå_ÂGÂWËYäW$y÷ýeSmD¥Ë¥Iâ(\WÎ½g¸1Œ‹Z«éÃpŠnªx	FfÁ¯G‡W’ðr¦“N=Õ"ÿž4¹Æ ¾ÑÓ‰’(Ðe7'îðÒé9úˆ$é’ dcS7æÉÛ£õƒ×ofkÌ¥™oÝNl!Ûe§ßÈµº¬¦9®cjX"«²Å'o—½å7Ê+ÁfDnA-ñ´m–’8ÿ2òÆÓÚ•ÖeZG‹g-4/€Wòh©Å;ÑRøg¶(@cH[ñí£âOJž{¥éôRk©ˆ@Åá¨¾òë‰‰`Ê{lï„+wðäkŽU¤Õv¢E o¤¡]µ.5¯Zž‘;äÞª
œ›|ƒlFhR©ªÒFš=‘=‚&¼²ZàXÚyjÁ{ä:G÷ˆtï¢=ˆÜèééÐ‰\?èÕªkèîÊ…à%.	³Ôß"C5’	ªCE[E3ß˜«™'·õßEŽØc»‚ {ìùæ~ 5à›~€šðW°çù<…^—RèãåQŠÛó‡÷'Y~®¬ƒâ5©g+½Ç68ÃŽ˜pœtªäeÚ;‹£„¥lb_ZÅå’—mKdÓñwBÂð¼œ¿	ßÎ5µj[€BVå'Rñ#;C7bhAqÖN.¬‹‹ÿ¸)hàê-:òðQ‡74ØÄ‹øUM,„òÛöIýïCEÖÅÝgÈ\ûogGèí­ÿßÜÙù¬ÿ=Ê¥ÚrÝ'Ú(xÏXãL{._kìü%Ç&Né™¬(ÿÊg­FN\ÿÍÃ§&ÅÖ‘&ßW/[|ž²â]bŠÆT-3Š­ßø\¾c@§ƒïOâú3Âø–5üdF‰Ú„ÑZÖ¼Ö>‘¥ûÿƒ Ïëÿ›tü÷v{§õ¹ÿ?Æ•ÿ;7œ7%êzé ÑDl§‰Êó”¦ö'¬1bËEÅº–G•&¢I¥tøã	„TüçSŒÿ0Ú·Óó?;[Ÿý¿r©ý_‰ïŒ<ÁÅ¼Q9ü—÷GÇ?ö_ïÿxÒ{¾Yy³ÿ/ýƒwo!ËV~l'_l¨†)m×G45&èYŽðA!ñÐÒ>æÐWŽ^áý<JÜÜ½û•Ç4›­ sb†bÁ{ñFjà”º&5yE	NN5¾@Ø`Ú—Ïo”¬·´ÖXc_¾ø±ñbÒx¡ÄºÆxrAãP-ïª«T=Žf²²uPU™C.ñ,ŽãÒ®žh€H‘ZŒæŠVGêY¤ÚÅÆw¬Ô-ÓŒ©ºD‚¹¨.eÁUœ¿r·ñ¾&g2< ,zåvx’ûÚ<^ Ö_RþsR=üG›OÊÿöÅÿïl^ÿõ(×"ó\Üo(K±¨ËSØhŽI¶„(GG#aàÙ Û˜aÂ`ý-#v‰ù“x~þAB›¬•k&¤G&Cw©Øl65a¥ž]”³ØRQ‡Ú¢bà`þ3¼‘‹0…wñ(R2|,2lðZý`úÖh&LäØ€xZF¢Yþ7K†¬'ONº,¤Y›)¶«bÊJ8ˆÃããwÇ]öMtNÁPa¥Ôh{žº{üî/¹ßéC® Ÿgÿ·äúïííÖæÆ&®ÿÞÚn}^ÿýWÜþ¹ûÝÞKØÀ%û¿‚É·µk{›â¿?ÛsÝ¼ išŽ0§ï¨Õ5öâ¶ROÛ^²Ð
m^É=ŠNäöÒÚzð=ôƒpƒ§Odm:ÄðrwÜa´RO››Úžºé‘º»>îìU*»†u%ûîµ¶GƒúvèÚû¢ñ•ø”ù¬ûãÅ$,®tšÆÀ5f©4”n¼•HÆ‰0Ê`Éô‹¬Æ…©ûÚÞîºµ''¬ÔÀ‰lëã­4p‡uy€”†û±¯Ô«KJjëÓ–‰±€½Ñö¢û|Flw^— ²oR\@OÃ3–4~´–&¦Ô´DÈ	¾ÌUO\|Ótíæ&š/½½Õ˜Ü¿…T"¡Tœ/œxq.…¤7‚Ï²¥4Añ§¹Mf4.|PÈ.t¯Ñ)kºÁ4qO"y0L¬0¢ò tükˆ¾èÞ¾˜C€4ÛbL©d[ý*îì%á8• ­³±oŽ¨E‹Î7¡&NÕ#0eŒ•k¢û 8¶9
E}^é(Ì\RbËê£/Õ¼»ëÈk)!“Lšz,”W÷-ª6U–3rCËÚ²éÄŽþ«ˆ¬l²¤,gÅˆ¥ä{»´/(‰½Æ\4€Y.™«üÌ413¹ƒ	:¯D~”É'Ì4pýÚY‰H¹æ@¦“dTÀH_m/!Ïv×1UIåV3iúm?5ùÞ‹už‹.€ñŒó,é”ù€D©~÷¤{Ccþ8.Ãž?
ëáìÞ±î\˜wd><ÍöË?ÛñU˜w$…ñ±ÇGA¶œ×Åã­r[dAlÎ± ÒƒÕ†å•GäýhLrÙEOBåm•)PSûÏÉ=V…§°:»ÃÄ¨DÓwðXNŠ§iæ äå`4µ3(µŠhb[{'œÃLgèÏøÑ¤µƒ±~€B­æ‰UœóPf¨ìAeÊøn4Ð	B¦V0õ0. <£½ÄÒJTZØåçÚ]ŸÚ‹ò+^¢.Èˆ¶u1S{ ØðÔò²ªs÷-ÙÖ‡0Xqwð…b÷`¶@cDçôü4Zêi”ç;êNtð:¤yü~y&Úsš6TøA @=@ñ¾{ë‹[ñ“ò©<ˆÿ'öÿñ¸Xî•¿?ß^åþ¿Öævg;Úÿk³…þß­öÆçýåZÆÿ'&ÿ”MÂîê Ì@\Êû71J½«JË=nE6-—E7\ã¸ºŸ‡åæ:Ù¤»l®·ºÿÐ»6.¼æó§âÀk*£¨îwpu­L+e¿ÿÚ·¯êË‘/»’„‹÷Å¾›²¥±‰åÐoš^Ok/¨¿+þIÜ	þƒÜ	þÜ‹+ÓüÏm¿ÖgKºƒ“ôV¢lîFðIñö<Âoù<—šFhÙ|_hqäâÙæÇ{uñ.éõìiòóqüAÇËÖy%¯\g„s¼»÷áÖ}"oî<ëF¨2ëò“0,~‚òsR)Å¾D§ÇU´ìæRÊùa$2Ò>ŽrPk21@Ø³rÊÂeTõPT8Óq³gƒRh·I8ïiñîW­5Ðtp=îúuð[Tõs¯Xÿ§c=ïWñ×ý+ŠÿC ½ƒóÿ[;Ïúÿc\»_¼~wpúãûC†-üˆ?ÌÖ´v¦i‚F86¹Þä_j˜ÊÔÅ°‹[†éæf
äé7‘RÎ?qàÊ2¯ii¶´zÚµe„ãžaâ*Ž=àVVhév#ê¶Ùk7¥¿`—dÜÞwtô¬buì®óÑW¡«ó‘h†:!‡†Óü90LÛºò›Ž®;Þd} m€õî}½ÕÜh¶ áú0âMÐ1šCœÁöMÄ\8³Í`lšr:y—ÞÄ%5KnÎ‹]k¶‹2ÈÔýÆ…¯¸dÜ0/ÖØ³¶ÞÖ;&k½ÀûíN{ÃdíVëEýe Ó›è‰éâç«qò³Ð×»õ‹ä'Ý¶.œ(–“ Ë†&úì’	0ÊÒÍ¢U²‰n£»&Iˆ¹E‹«ê_t<²tÅZÍÖVªJ˜Åð]¯Á ï‚±8õkí–÷1¶„‚z{YàÚ–QPB;M3ý#gª.ÛlØäWñi®*º¬©mað#.ßÅÆÍ³@P‡võxœéLQ·Á‰[6ìs¥!o ãšŽ›c‘ÙT©O0¯±U¦}Ž7þ|ŽqYÜK”3H0¶LÛhà&ã	d¯-ÑÖÆÅ¥À I1Ç¨XêtZ'žA…§RM£/_×0QƒÚ…ë[fÐÃUuVËÐàÖ(='µÈAÌò‚fk23î5»µ™@êù¸/üm8wåË+˜XA`áº‘n˜,»× \Û¹æ4O„õM„çí|Ü¿„AÂTm¾1´ÝÀŒ‡
j„Ö|û!*©ØºJT”%¤ýü6…„Ð¬%éxâ«’T;…¢‹ßQ–B#üƒX¸2×@9ŒâµÜåN#TÕGîpÌ©åü»WBÈ-½V#„Œî—ÄˆŸK‰qw,´uÝ€AIãšÎ–wŽ¹:³U§OwùR!øÃUÔ«ŸUíj ª‚m’’õs€‚ÃÆ1—¶0:úÔêñïþŠí?Ü%ÿãØíöfGÚ[­Îv‡ì¿íÏëÿåZfþç5èYUÏ»ÎûDòç{ØEcSU9s4dÐRá&˜$TåŒŠŒ‡æiÈ‹{Ú¶Ú0mÛØùŒõ§8R¨Áv^FµÆ-
þñ0ïJ€Xóå¥ð§G
~.*†ŠŠíï– 	?üµo÷û"ÍÁûŒÖ#/NíE³=Ò~å>ÙßÛ¢9ô¦èCñû¡Ìs6Ó½gB °c«IüäÉ¡â•'e”{ªE'À(ÒØ&â°c3p§þÐ\8hg1u=g^+íë˜áµi:"¬°Xƒå†ÐSæÆŠ¤ó;I	œC1=ß½à+XÈ
¯p¿}å}|¹hˆ¦€Ñ€‚1¸à¡‘žp@A]bìyl½{ˆLãò˜MÉ»ö][3Ý«q¶vNZ`11ûöÕ§Ê×º§€óRï‡å‡ÂP¼ûæ‡×VpyWn òr1^ ”¿Nàî½bFˆª|lp§8éOq¼£ðTêP|Ôû~jé±ÏUÉ†¼å–'•ëçÅDˆ]VÐÈŠHx˜7›ë/Ë„x€uá:éÁF˜QJt‡©žŽy\ˆ´ræwß%Ã,èÓ]©©F¬Ä˜ðÍï@Î8bæÈI	Ÿ&-Z†y®t½»QP±·?EòÍvBÝouò£!¶#¿ã0Ûû§â*ƒM~ìKìA‹Ñ×û?Ó$Ú®ô¯¯3\}Ñ€&€ÑtÌÌ+8³ÝbœMƒJ`†§ÖÄt§a­Vg½=†'ãxÐäûBÖêk8ïÛjÕ_VbÇó“à<ñûºã˜þC8€çíÿ±¹%ý¿Û­òÿî|>ÿëq®eü¿(ƒ_—ÜÙ¬€J,1¿Ïøÿ{ßýCÛ;4¬Å¸ßï–«h*žB+ÎÐF'œºˆ˜ å]¾Ï'ˆsæ@Ù~×qOšnpIÚ-¹jàbDfîÔ'âp°ÁâþjhÔù~}ñ	}¼—Å¬§E÷ó8ÅMÅE)2|TÄGñRî¿ƒùŽÍ™\õÅ®,‘Ï®cŒ°Ym}ïýDsÏÛ¥ƒsArE“È‹Ç:?ŠÝ‡»˜'X´˜ÕÖ¸Ë•Ï±S™á‚h¹:²©ÉÝL¼Ûe½qíëÞË<†t}V}ëJÆ‘'ÇÌÌ°Jì
Ù—ToŠdÖ§¸ÞØÓm3£µÆoOŽ@.Û.Jgcqßqr¹1Å­pXf0Ô=“VZò½ÿé Æ ›¿FX©oˆ;†ƒ®x`Ï[W…Õ¡t‰LŒg&¬,FgŽ£Y‹Óøå	 =¢·ñ¢És~jHQR<æ/­ÀnG0§ñ÷vCcïØý ôôSkcã¬5áÏ¥H(0dï£6ÆèrÇð¯BÝhßì…oš þS ;w=3mÛ½Ø?ÒM
øÆÝ€ì©	 _ÁO
ðæÝ ã‰§N¨ì7ü.~ënà‡3É} ?)ÀÛKÞ{jCÆ²¼°÷ä¼QÕI8‘¾÷øˆrãî#•‹»G•Õû‡õ	:b
Ô…ù/_ÈÃoìò9ð*ãq4“
‰üvY«¹³å›“—¬h\æ¼ðúoåŸÿö?þùoÿõþÿŸ ú¿A­þ~øÝÁ»7‡ìôé¬üDQ¬.|†$ÿþ0¥ÿïŠ©•Š¬ìÆäŸÿþþßÿý/€ÒþñÛ£·ßvÑÁ1v} ™ÁÄæï{–Ì	ÝŽïMÕeA0n†ã©ã\ëáXwl\º@ÃöI¨‡Ó Ëbº¾Ã¯¦„”£ÕPƒ5íœÐØ¸ó–Wd®3´­á%Jo&¸¬V_tÒÚ¶<Š’‹†dÕÍSgŸá—ŸÑÔág5&0€·ñ?Ñ[zì_úC°fÌaË3g*ïRì™áOì__ÆRŽ~e]à„Íˆ]š×>È´|k¢©êMÜ¸Zøýâ5*ˆ^«Jé-n‰=¨%¨/ªbùÈ-üÞþü‚éý?Ð…}ß>À9þ¿­ö†Üÿck÷nýÿö®u¿m[ÉïS°n½’›ˆºY¶ãXÙæÚæœÄÉÖi»=ýe]Z¤%&’¨’tl·õÇóûtû$;3 Hx“ìÄxN…`0 ƒÁfºð×ÚÿïF®*ö?éü`i`â,‚l~Ì‡™gðí©,÷»¡HAî<þ‚¤}j» ¹*…¬<@Br¿ká8s£ræ:Hj`ì‚xô'ñÅ¤t'~>Œñs/dŸ¸Á1Cey×€+	–=v’Š!´¸ÿ„eýÂ@†ðzÕ%üuÔ:jL“:È]»Øù¬½ñ'68¶B3ýÓÐ9Í†ÈÁ@G|9ÖÇ›è©ÖÀÆœ ™gèøFT¢÷»ÓÌõoc=,¾ÙmäòYÝ»ì@]€~‹:;tš¬šŠ8vº9`æ/¡FÝb,Öix­¢ìˆ&‚Üi¤®K`ÄÐNÉ©Gdqmys§V,WèåÉ°rA&1,Dþ<ÉÊXY–*ýhßËQñóÖ£†t…1PÌsÌ üë~wç-pØ4ÍÄíVwgÿm™P½¶K$“»%Ò_rÍPgC·wŠ*ÍßCåH§<—²¶f÷Š¼Ò¨‹‚Å£Cq<y¸!V5Ì8ÔñøÄx`tò§+fšÁ²®`Á òÆ'„=lGËI²K,ŠŒª ³æO…8ÈG!ê
#$¢Ä¹@¼š?æp(’Æ±Œ‹I‡u2²øÇ,7ÕÄ|ƒ0Ž­¿ÈöTˆ‘$ä?.%¯³o£%QŠáUÔµ5…5=Zé¤aki	8P<ò©'¢x^¡£SÊð
åõ÷ûepŒé×]¼ß¤ÉE‘»0
” }e8é…?ÎÓ lœ±ÅI'àÔ+Áø!­MÒº€Îý´Cziêhe¸k4RÊ}îZ‘µÏß·¶1ú7¶}Z%ÖRñì˜žê‘p¿û»Dä±k9ñ¹M;`Ã4Æ˜2Ç'Skþ¾B#÷[¸dLðtŠ©i æ–q³š7W57ôÆã©£k2—pQ˜—Œ\÷7úÉ²qáøÔìäÎä•4	h]caAÑÂo	I@6°x*ŽÁ[¦œËEÛQ¡|ëK}:gÏs÷VùÚKŽ3|¥þdCuý™ÓToÎ:ô'<óçJàÏšžË>5wÿ&¯v|,9xü6*‚Ð·‚É’ª¤º3êz%$‚~HÈQ¾bë‚¨°xô_¨Ú˜…wèñP´Ì¦té„T}ÎjFIE¸%l„ ä‘¢­ü•é_|ÙjqP(/=Ûš­ÖƒDgtÃÀl087°*zeæ	9ò7"a’ù²e»ÖÔì‰¼:Ùw…Cnrlfì}„"(·f²‹Þä™qk5Ç¥ÂÏÑ/qþ˜	GCµêÂÑ¨†e¦m%‚yÛ-†5>¼'×@Mp¹8[ä.‰™0Å ?¾;¦1EÃ	Ã@(–íÍ§9¢“Øû¦¶½Ï|oöiä3	«Zv×K'‡×¾õ]ò¬‘öûØ#â°1ÿd‹ÞÌ=Öz\xœ•$ æ<,I3˜ÛÏíä¹':CÃöFgøíŒOÙ«.ŸÛÒg¬zßàö(lò{Ñ·Î…3zìÍfÖÜn6°zAZõ2ÕIuès›­Í>[ê„£Ió7vÕþúOöÞU¥ãoq–pÆK)s£â·ù.ðæÍ­ô«(H’Œ§FŸôÄÄâ·RHqOî&E5FV‹’îgÊ™;çF9‡Ä|S[v´4¶¶Ld[3ïŠ­˜YrÅ©ï{~”Ñ4É)š*$ú×çv\ú·»âó_É7qÅÀñ_ww;qü×Îî6Ëÿ¾½>ÿ½‰«Fþ‡Z™ê™f£OLzYçTï£¶g£¬WÏ")kóŸQêŠÒQ	ëF#,²/¬sP7~µZ<lý«ÓºwüöÎyNk+«ïŽ(¤±5
q#º‹ G?y¾c .\lm¼>Æ—Ž‚¨e|AäÃ"Æãþ .¢»¶pòy™„ñ¬¬ð !ÚUˆàî‚=ZüaÌžäTï\FFQVæ´½Ùr[Šë<9G³s,™e•y9fÖÜØ,3G#ï–rá¢Ã‡‡ìÑÁv—tð1§áKë"ô¬>ÿcr´åº¢—ê	èÖî	h¥;;›ü9a½÷ÎCŽ×f¡ìàš]46o}Ì9ô@‘5š¯(S 5-1%R‘s,@–|ûeŽ4“Þ‘Ï)S¢55¨tÃ¢DŽ4ŒqýC‰“ï
™Ë¶•æÏ	&R2_Ì*œÓm¾IUHG~Ì³‹(xQÊ}NY7+6æC@¢„ÜWÔP"ùfNÞÞÏFDº¶ÅdrARE'4„j€Q¤' Á»£IVðCvªŒÆ–,†Rl¡y^XJ0˜¨Ü©SO©#m²<-pC6Ü•ÍíBw'
G#EÚUm°-~FþÆ]ìGæ8zŽ4¼dJ(ô
LHro”xÄyYÝð²D&Öë‰Ì™ë²ŠXÂ¼8uæãpbnï¾t›§ûÖÉÈvNÇ÷Ýûélî-~÷ƒðìÃùÅå=~òôÙwß?ÿÇ?_¼<|õú¿~8zóãO?ÿ÷/ÿêt{ýíÁÎîÞ½/¿ýêëÍÿùo6XéSyDBáü6²¬‰Ï\¸Ù¹pÊà÷;²E/úúÎPPiâßÃæK+œ˜§S6šôÓ'}üMô&+tKd“ÖÑ´ýNT%™Å­ë1´ÅöÚ'ŒøÏ;»Ýmÿß…büÞÿ#WÕøõÐÿ+´þHJb*sž¨làµCNÊš€ÖžÕ<"ì+7±ÐŸ)Ê_BÇx„Y¤_í,•ôWÒÃœñòXp=ø÷º™!ø«ÓÓ¥©¿!<ýC¥cbìsI>•QŠiYÅˆ{*¶ê¾›‹º—ê.Ä På5Ñ÷ôm‰¤.µ"­tˆ$[åÀÁ‰âî*ðR’¿cfÓK ãS–¯BÜðmžvŸ5ØzõìdîãUœ=`Me¶dûÆ¼ÏÔ,=ý%üÂˆ´yhV¹®e¸º¯ß-˜7Â‡ý‹O(yhÅZjCã—]BÒKè[7µsVWÑ¸JOUûaŠ‰ùdèN4äãáò5­\’ÏÀÛl¯wniä¢¸¯åŸ@v×ùKønƒµ+GùÂ¼ÑnPä­µ,‹ñFØT/‰ñf1	o-Ê;noéõó{—‚ÍÜà›­ ˜¢®ì-Uv+œœ—îïRh›îoAÔô·¨ìóèoöê“êmFÒ† ˆèrÝÈ``´ÜÆ¡ =ÃÕO}ÏÏÊ}cA@ƒz×ÔÇÌœÖë}òýúi:ïÜ:¥‹N¼Y{£»Ñéµ X{òÐ¢ÃoQÐýÂãEFqrN=UÅFÒ¶eOšœøZiK•²–®!iI:þÐè¢•
Îÿû^Gœÿäÿ1ô×ùŸoäªÿïˆ… Å)2¤“xk—Î&—^„ÆŽå‹l
¤ž$·ªÒj!ïY½-J¨’Ej¤ñÐ¶}J¦Ñ"´‹}XJÌõÌÌÌ¾'›‡<\%EÇO¯@‚£Ó-<-ª¨±lã¥e5ÇXèÎuÊB,£Ö±µU8[ÀëÉn`ó´< Ì¢;ö:üË¢Pv{bÇ
rlÉ¾ô`¯c4¿óæõÖA›•Rºšíí~¦¸§«±šŽ
ª‚‹>¯¥x×ë¢7/Ž*ôP8–ë ¹7wë 0âÞÓ±îÐÃÈõ»‡¨LÖëª ¬¬WªÌ?MúN}gý|d|ï[¸¯w( ¶¬ÃIÐ%pû8¬iË
LÿÌ}ç:<_ ›eU8•*¢šËl¨„ ;:|Þ~üäpÕ=!Ÿ“©(^™ó@Qz"±È+¨õX.ãg%r¥,Ÿ%ü2T™=e|$’“_^ÂíÕVl2©‚
Ï>sˆ|Gy^ Î›‹VT½„éšD'‘¶I'ªK…MëKÕ‚‹–‡£–:šDÁÄÚÔ
£‰ê Mqe·ÍƒWî¸Ri×:¬˜®—7˜òÀO¤F¡sÔ—¦² ƒ¹ÁDù¹h<¤Æmì#RuêvªRy=´†Ü¼0äU>WôÒŠô!L‰w„ø+0f´Ï_·qÜ¼¶ÂI-µÏƒ¿™b[sýìœAY˜5®þÊ±ÃgBa¤}ëM;Y½©@eJ§ÌúÁuæPz+PcÏ²²´#Õ¥A¦DÂù$£ƒœ'í¡&Ü[ûj>¦7É«…ƒVíµ\Z¹öXM4þŒpç>
@ý/1Þy:Æÿýï¿³/&Ý"Ó½ªá‰ˆRª8T“yb4ŸACO¬Ñû3e¯SÀ“9íÏu¯~è…1w ¥Yò	0­#v­/ºäüïÜú¿ò:òÏzíNŸÿìt¶äÿÙßYûÞÈuðå“Wßüòú©]Â	ÿ2¦Ö|<Üpæ1°$CàÀƒ8áìÁÌ	-áì<ÜøñÍ³(²{Äìs˜×™ÂÙ›Gü2×ýã®áÎÝÐµ¦­`ÒkØ5Åòp@K÷¥Kªâê ÍÞÿ‚‹ìù{nLš„á"Øo·GöÜ|ØÎÔýà›s'lÏ³vt:üíÀì›ÓAØAüÀœ!V& ¤ÌÖ„üÇv>VUúY¥º[.êÛ5»Ðú6â8ÒÏˆ ^Õ/6¨ÿ¤b;âò9&5qc9:–ßû–íB4»}×øªku­žct6ñ÷N¯Ûw0·Âf*ì#4¾%RNÀã“äcž(ö+§ƒÿ‹ŸÅ›Ìè‡	‹%ŸÐ’êO¬foç®ÿmÃóÞ`ËøÒ‘YvÞÏ|jûÞáô¡ÃÒìúÍngq‘jÃ‰çÛŽŠbz3hÆâÂ¼©kó
¨1ú£cv·Ê´£u‚~ÿ©Öçœ³ëÄ›Ú÷³Y^Ô®ÙÇ´¨Jfn[÷œÓSe»5ô(9E‹(í¤ƒÿÓrÆØ<pQÙÇ°>Ðþ~`8°.$_[X¶ê%tÂ.þ¡íÆpr˜ëqoq‘T–?vçXV‹)7Ô¾ý‰‡Ö>u+O5#rÒclwû®ÑìUéq¢Àä±ë—#A;#wvvÇb3rwgûÄê©fdbŒ:%™g¸)ªY´|VNÇd†cb´vU5®ídç÷ÂƒëÔ½pRó!ôÐ„ôð@§³}yTùìMÝæ)dzƒNº”bÉ²œ8áœ«"Mˆ!b"u3Çá}:õÎ[—û
'ùôÁÿIçwú·3Çv-£9³.Zœ?»;0	Ó‹5]wAKÁV¼d™oê„FÒÔ¨¬›`VZ:åËV|L+½Èˆ	¼øˆç%k§êU)ÖBAkï)X[‘£sé((?d½Ì ãZ4÷ö2µæ¬÷9“¾…Cwj¥õÈ/
÷Ö)2
åB§„PÒ«”¨È„ÌOö3-¢ÉvïÞ½JPçˆ¤ªæGæ®")-c:YF"ªºpª,ù
ßíe¤¯wÑ
&–íã\ácôáø™æ|·`ñÅlˆ­¶è–Tª¬ÛéÁrOÒ¿¿ÍZMk,{Ø5`˜*0¦Xs5üÌ”Ü+h‹|¸^Ce/§ b““®€¥rUŠ(NÅ	TEKž‘ï³Ÿhø¥Ùê)F–<pÀð.þ¡æ÷v¿C›Æ¬æsJ‘EÈõ–ÿ)Ã261¸N¨žuýJÐPK~zoÚ™?mnàÆ}Ÿn´ƒã;³éÝÍþ~ðs¸…Ýèùù¹yÞ7=Üî2/7Ü­?ò.†ð½ÿolöø~a…
M÷Þ6°E›½½L›v7{÷ü-T8‘µ€·‘Äè6&Êó)_Þ°ÑíD·™M Ñkö°ñrÛØôzðWwÀþîõáïF›Ñ‚¤Â¯ÑVLÛâƒ6³Sà¾˜ï˜¡ÂdÌ7¡œÅÎÅ6q­éXÜ ¡B+.ºèK°öZÐD¿u:=s3˜’‡ù©Ñ2s0ÀqÒÕ‘<vØ2ò†^S²åS`Å Á“‹ìé¯ÆÒJD[Ùö†AºQá²R  ‰ëL™¨á€„¥&ETK#É‚ª¾ªêTà ©7öÎB5,Hà&ÊäÄJ·¥‹O*oÏª-KY!8H: –+bœ¦´ˆÄ˜xÅï‰ º©˜œÌ¿ÕÙlžÂò á¶, (Ø	BÓ™ÛÏ3ð$ÆæÛ'R.;¤Žc{3äFOx®[Á„D
ÆTé&°›É›&…;ÎÝp'ð|uûeñ²\saáx‹ÌE¿»±öóyÔØ*Û8þÁq¥FréK¿#R;½b­¶½ØeS8uƒ°tIŸ”lÑÄ¶[?ÊÛÃ¼®©5!Y­=2¬²Ä@Ôa&©a«o’pLªØ¨è³’Í’\A’þ)«lÑ‰5ŸWüõ’-H”A!ñˆJÐ7/Eì§zaI$B€zòÔÍÀc'<>…ï&Ž},n7ñ¥ã‘±ç»N0ý3g+Ac\‹ŠR ÔxÐL^Ðå]ñ2FÐÌû.Ý €ùI™j@éIEÙÔYfÄj°$Ñƒ«+þ%8ábHfÖAŽ,cÁÐ+9L¨VŸj²TLE^}-¬f"KöA<ÈîÑ @ï/évÚ,…6`¿*ÁüQ³ºwòQÝ	l7¦Ø½£ˆ­ñ U·›yÒ&4ïÚFâE9=Z¢œ%h¿åš^‰"ø›rIÑ¦eÛO?Àç/€YªÙ øpã®! (Í´ñR˜fi¸áw&Ûi@í0ÐÓ‰á’•øè*‡hQÊJ¨öèÓ©Ö}¤¤šõÈQLíÈý+€yDÎ6žÿp:m6"k{t&#/Ê0aú=µF“&­'™„ìª:sðÂì…ç ~{ç¦‹KÃÏ¸ïÆ°t»;{ª÷«3µ6s#&'î\)ØŸœÒô‡Ê	;%s@’5à Íñq¯ÿ“ÐÔW
*ðÿÞÝÞÞð?þ ý¿û;kÿï¹ªø'¶`K»‹Ò~z}(‡pgáÑäTƒÏÐÍ:m%¾áP`íçÐ9Oº†-á®ö§Ê4‰å½©î{XiLçQ™“˜/á&I}$b‡iýÄË9úÖjâÌÏËrÀ4¿{”Ÿô)7Zh“EºFú­G:°øÿ8§¢;Š½3è`ŒHgÏÍ.OÑ¥)¤ö%í°t¢hÒø—òµJX[ÃVß(Yµ”ï¨À¾‡¾\Ö#³’©Xé’¶ñQ"Âêä'Jh]_ë»‘¢ˆdRU)&Y"‰<ó!‹ëËjò¸¦Á_<?ÏÕÕÖL®­ZÔLhñÙ'³À|N…éæ±œp{Ìî43¶ŸÔÇ0äÄ·C£Á«Ö3’ÈYUëi²ê'n€gÇvÊãT¢”k‹×-"”Ã€àÄ“_ã§´;oz•óS{ÈV“:—UÝ»ë»qgVDÞ	L¶÷ñD·ˆ²ã÷Îå¯ûÛ·ÀxÓ4[½ÎþÛÕ:£×o/7¹E\ÿmðÇ+wÝxÚÒ/D+m•\±:y<>1ü	e|ØØ4»§áÚo…MiÜ>¦òÆ'[ÉôÉZàÑwÊ¥‚ˆœI}oLÁÈiN1¨¿Áââ~ÑxQÖ" iÌ¹@¼š?æp(c±ŒExâ˜$—(ºx[848ÖÌ²SMÍ7ˆZÚÊéJ"­³õaZ€í›Ñ¼–MùK	ý¬n´¶EÛâÞ¯)òéÑJçUah]«“¹eJÅXÔ«2 pm+ÊHCûvVbÍ\'ŸvN¶ŒÂ**T~ÓÅæJ¹,Dz‹*y,ääé!®Ñ†UNa!vk¿k³9ä„ º¶ÔÆcø—¦‰Kæ¯fg&ºFß`º	á®½D¾	<`]XÐ€†œŒ‡»Ðäk`30Â„œ.·,“+ÕúRŸÎÙóÜÝOô¬b²Ì$×™”¤LB’%GC]T >íÈŠ»ãÏ7"ŒÝqÎC5ÓÃpL}âxT2qæ[›5D°MÞù}¦iCd¬6¢<*AF•Õ;Hžçl¤qe	5Ñ.çð]_Š-Ð¥VÞä¥xÃn6"
–ÝÔÂb¾Pë+ôqmº/"+>n´Tñ Ä…¹ßÃ‰¸_wç‘ä ’qªY‹E2nM|#ôŒèûÂpøÑÐDÄ†tù øâ“åââg›‘’kß(îŸÛL8¤<l¬	§N8š4òí¯ÿdo^µaHü¶ñqöÛh³ƒ¼¿Íwâ>Ò¯¢´ËÂH
‚OL(]ýÐÂ¤é…Üeá•Âï‹5KŽ½/vÅè,±¼3ž"fQˆxôb0BqB¥q&’_å:,ÎúZ_ëk}­¯õµ¾Ö×úZ_ëk}­¯õµ¾Ö×úZ_ëk}­¯õµ¾þ&×ÿÔš#« à 