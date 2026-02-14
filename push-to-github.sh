#!/bin/bash

# Helper script to push to GitHub

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "GitHub Push Helper - SSH Panel v5"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get GitHub repo URL
echo "Enter your GitHub repository URL:"
echo "Example: https://github.com/username/ssh-panel-v5.git"
read -p "URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo "❌ Repository URL required!"
    exit 1
fi

# Navigate to repo
cd /root/.openclaw/workspace/ssh-panel-v5-repo

# Add remote if not exists
if ! git remote get-url origin > /dev/null 2>&1; then
    echo "Adding remote origin..."
    git remote add origin "$REPO_URL"
else
    echo "Updating remote origin..."
    git remote set-url origin "$REPO_URL"
fi

echo ""
echo "Pushing to GitHub..."
git push -u origin main

if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Successfully pushed to GitHub!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Repository: $REPO_URL"
    echo ""
    echo "View at: ${REPO_URL%.git}"
else
    echo ""
    echo "❌ Push failed!"
    echo ""
    echo "Common issues:"
    echo "1. Authentication - You may need a Personal Access Token"
    echo "2. Repository doesn't exist - Create it on GitHub first"
    echo "3. Wrong URL - Check the repository URL"
    echo ""
    echo "For authentication, use:"
    echo "  Username: your_github_username"
    echo "  Password: your_personal_access_token (not your password)"
    echo ""
    echo "Get token at: https://github.com/settings/tokens"
fi
