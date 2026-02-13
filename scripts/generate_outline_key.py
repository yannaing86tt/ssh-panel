#!/usr/bin/env python3
import sys
import base64
import urllib.parse

def generate_outline_key(name, password, server, port, method):
    # Format: method:password
    auth_string = f"{method}:{password}"
    encoded = base64.b64encode(auth_string.encode()).decode()
    
    # ss://BASE64@SERVER:PORT#NAME
    key = f"ss://{encoded}@{server}:{port}#{urllib.parse.quote(name)}"
    return key

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Usage: generate_outline_key.py <name> <password> <server> <port> <method>")
        sys.exit(1)
    
    name = sys.argv[1]
    password = sys.argv[2]
    server = sys.argv[3]
    port = sys.argv[4]
    method = sys.argv[5]
    
    key = generate_outline_key(name, password, server, port, method)
    print(key)
