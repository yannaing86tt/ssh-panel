#!/bin/bash
USERNAME=$1
PASSWORD=$2
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
SERVER_PORT=22

cat << EOF
Host $USERNAME
    HostName $SERVER_IP
    Port $SERVER_PORT
    User $USERNAME
    # Password: $PASSWORD
EOF
