#!/bin/bash
username=$1

if [ -z "$username" ]; then
    echo "Usage: $0 username"
    exit 1
fi

# Kill all processes for this user
pkill -u "$username"

# Delete user and home directory
userdel -r "$username"

echo "User $username deleted successfully"
