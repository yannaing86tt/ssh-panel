#!/bin/bash
USERNAME=$1
PASSWORD=$2
DAYS=$3

# Create user
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Set expiry
if [ -n "$DAYS" ] && [ "$DAYS" -gt 0 ]; then
    EXPIRE_DATE=$(date -d "+$DAYS days" +%Y-%m-%d)
    chage -E "$EXPIRE_DATE" "$USERNAME"
fi

echo "SSH user $USERNAME created"
