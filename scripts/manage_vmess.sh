#!/bin/bash
ACTION=$1
UUID=$2

CONFIG_FILE="/usr/local/etc/xray/config.json"

regenerate_config() {
    # Get all UUIDs from database
    UUIDS=$(sqlite3 /opt/ssh-panel/instance/ssh_panel.db "SELECT uuid FROM vmess_user;" 2>/dev/null | tr '\n' ' ')
    
    # Generate new config
    cat > $CONFIG_FILE << XRAYCONF
{
  "inbounds": [{
    "port": 10000,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [
XRAYCONF

    FIRST=true
    for uuid in $UUIDS; do
        if [ "$uuid" != "" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo "," >> $CONFIG_FILE
            fi
            echo "        {\"id\": \"$uuid\", \"alterId\": 0}" >> $CONFIG_FILE
        fi
    done

    cat >> $CONFIG_FILE << 'XRAYCONF'
      ]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/ws"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
XRAYCONF

    systemctl restart xray
}

case "$ACTION" in
    add|remove)
        regenerate_config
        ;;
    *)
        echo "Usage: $0 {add|remove} UUID"
        exit 1
        ;;
esac
