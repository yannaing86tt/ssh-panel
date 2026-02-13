#!/usr/bin/env python3
"""Generate VMess link from configuration"""

import base64
import json
import sys

def generate_vmess_link(uuid, address, port=443, path="/ws", host="", tls="tls", network="ws", remarks="VMess"):
    """Generate VMess link
    
    Args:
        uuid: User UUID
        address: Server IP or domain (actual connection address)
        port: Port number (80 for HTTP, 443 for HTTPS)
        path: WebSocket path
        host: Host header (SNI/CDN domain, optional)
        tls: TLS setting ("none" or "tls")
        network: Network type
        remarks: User remarks/name
    """
    
    config = {
        "v": "2",
        "ps": remarks,
        "add": address,  # Server IP or domain
        "port": str(port),
        "id": uuid,
        "aid": "0",
        "net": network,
        "type": "none",
        "host": host if host else address,  # Host header for SNI
        "path": path,
        "tls": tls
    }
    
    # Add SNI if using TLS
    if tls == "tls":
        config["sni"] = address
    
    json_str = json.dumps(config, separators=(',', ':'))
    encoded = base64.b64encode(json_str.encode()).decode()
    
    return f"vmess://{encoded}"

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_vmess_link.py <uuid> <address> [port] [path] [host] [tls] [remarks]")
        sys.exit(1)
    
    uuid = sys.argv[1]
    address = sys.argv[2]  # VPS IP or domain
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 443
    path = sys.argv[4] if len(sys.argv) > 4 else "/ws"
    host = sys.argv[5] if len(sys.argv) > 5 else ""  # Optional host header
    tls = sys.argv[6] if len(sys.argv) > 6 else "tls"  # Default to TLS
    remarks = sys.argv[7] if len(sys.argv) > 7 else "VMess"
    
    link = generate_vmess_link(uuid, address, port, path, host, tls, remarks=remarks)
    print(link)
