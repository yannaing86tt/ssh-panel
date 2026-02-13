#!/bin/bash
# VMess User Management Script

ACTION=$1
UUID=$2

CONFIG_FILE="/usr/local/etc/xray/config.json"

case $ACTION in
    add)
        # Add new VMess user to Xray config
        python3 << PYEOF
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Add client to VMess inbound
for inbound in config['inbounds']:
    if inbound['protocol'] == 'vmess':
        inbound['settings']['clients'].append({
            'id': '$UUID',
            'alterId': 0
        })
        break

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print("Added UUID: $UUID")
PYEOF
        
        # Reload Xray
        systemctl reload xray || systemctl restart xray
        echo "✅ VMess user added and Xray reloaded"
        ;;
        
    remove)
        # Remove VMess user from Xray config
        python3 << PYEOF
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Remove client from VMess inbound
for inbound in config['inbounds']:
    if inbound['protocol'] == 'vmess':
        inbound['settings']['clients'] = [
            c for c in inbound['settings']['clients'] if c['id'] != '$UUID'
        ]
        break

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print("Removed UUID: $UUID")
PYEOF
        
        # Reload Xray
        systemctl reload xray || systemctl restart xray
        echo "✅ VMess user removed and Xray reloaded"
        ;;
        
    list)
        # List all VMess users
        python3 << PYEOF
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

for inbound in config['inbounds']:
    if inbound['protocol'] == 'vmess':
        print(f"Total clients: {len(inbound['settings']['clients'])}")
        for client in inbound['settings']['clients']:
            print(f"  UUID: {client['id']}")
        break
PYEOF
        ;;
        
    *)
        echo "Usage: $0 {add|remove|list} [uuid]"
        exit 1
        ;;
esac
