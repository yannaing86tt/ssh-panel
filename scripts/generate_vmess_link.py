#!/usr/bin/env python3
import json
import base64
import sys

if len(sys.argv) < 8:
    print("Usage: generate_vmess_link.py UUID ADDRESS PORT PATH HOST TLS NAME")
    sys.exit(1)

uuid = sys.argv[1]
address = sys.argv[2]
port = sys.argv[3]
path = sys.argv[4]
host = sys.argv[5]
tls = sys.argv[6]
name = sys.argv[7]

config = {
    "v": "2",
    "ps": name,
    "add": address,
    "port": port,
    "id": uuid,
    "aid": "0",
    "scy": "auto",
    "net": "ws",
    "type": "none",
    "host": host,
    "path": path,
    "tls": tls,
    "sni": "",
    "alpn": ""
}

json_str = json.dumps(config, separators=(',', ':'))
encoded = base64.b64encode(json_str.encode()).decode()
vmess_link = f"vmess://{encoded}"

print(vmess_link)
