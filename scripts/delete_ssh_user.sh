#!/bin/bash
USERNAME=$1

# Kill user processes
pkill -u "$USERNAME" 2>/dev/null

# Delete user
userdel -r "$USERNAME" 2>/dev/null

echo "SSH user $USERNAME deleted"
