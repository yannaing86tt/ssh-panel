#!/bin/bash
USERNAME=$1
PASSWORD=$2
DAYS=$3

# Create user with home directory
useradd -m -s /bin/bash "$USERNAME" 2>/dev/null

# If user already exists, just update password
if [ $? -ne 0 ]; then
    echo "User $USERNAME already exists, updating password..."
fi

# Set password
echo "$USERNAME:$PASSWORD" | chpasswd

# Set expiry date
if [ -n "$DAYS" ] && [ "$DAYS" -gt 0 ]; then
    EXPIRY_DATE=$(date -d "+${DAYS} days" +%Y-%m-%d)
    chage -E "$EXPIRY_DATE" "$USERNAME"
fi

# Verify user was created
if id "$USERNAME" &>/dev/null; then
    echo "SUCCESS: User $USERNAME created/updated"
    exit 0
else
    echo "ERROR: Failed to create user $USERNAME"
    exit 1
fi
