#!/bin/bash
set -eu

# Install Node.js via nvm and Claude Code as the vscode user so that
# npm global packages are user-owned and claude can self-update without sudo.
export NVM_DIR="$HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default node
npm install -g @anthropic-ai/claude-code

echo "Post-create script executed successfully."
