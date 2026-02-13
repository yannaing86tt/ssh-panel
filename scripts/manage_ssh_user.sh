#!/bin/bash
ACTION=$1
USERNAME=$2
PASSWORD=$3
EXPIRY_DAYS=$4
MAX_CONN=$5

case $ACTION in
    create)
        # Create user
        useradd -m -s /bin/bash "$USERNAME" 2>/dev/null || true
        echo "$USERNAME:$PASSWORD" | chpasswd
        
        # Set expiry
        if [ -n "$EXPIRY_DAYS" ]; then
            EXPIRY_DATE=$(date -d "+${EXPIRY_DAYS} days" +%Y-%m-%d)
            chage -E "$EXPIRY_DATE" "$USERNAME"
        fi
        
        echo "User $USERNAME created"
        ;;
        
    delete)
        userdel -r "$USERNAME" 2>/dev/null || true
        # Kill all user processes
        pkill -u "$USERNAME" 2>/dev/null || true
        echo "User $USERNAME deleted"
        ;;
        
    *)
        echo "Usage: $0 {create|delete} username [password] [expiry_days] [max_conn]"
        exit 1
        ;;
esac
