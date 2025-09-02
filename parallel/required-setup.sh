#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[env-setup]"
ENV_FILE="$SCRIPT_DIR/.env"
GIT_CREDENTIALS_FILE="$SCRIPT_DIR/.git-credentials"

log() { echo "$LOG_PREFIX $(date +'%F %T') $*"; }

log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip, jq, software-properties-common..."
sudo apt-get install -y git curl unzip jq software-properties-common

log "☕ Installing OpenJDK 11..."
if ! java -version 2>&1 | grep -q "11"; then
  sudo apt-get install -y openjdk-11-jdk
else
  log "✅ OpenJDK 11 already installed."
fi
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
log "✅ JAVA_HOME set to $JAVA_HOME"

log "🛠️ Installing Maven 3.6.3..."
if ! mvn -v | grep -q "Apache Maven 3.6"; then
  sudo apt-get install -y maven
else
  log "✅ Maven 3.6.3 already installed."
fi

log "🟩 Installing NVM and Node.js 16.15.0..."
if [ ! -d "$HOME/.nvm" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  log "✅ NVM installed. Please run this script again or open a new terminal."
  exit 1
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

nvm install 16.15.0
nvm use 16.15.0
log "✅ Node.js 16.15.0 installed and in use."

log "📦 Installing Angular CLI 13.3.11 globally..."
npm install -g @angular/cli@13.3.11

log "⚙️ Installing GNU Parallel..."
if ! command -v parallel &>/dev/null; then
  sudo apt-get install -y parallel
else
  log "✅ GNU Parallel already installed."
fi

# GitHub credentials setup
if [[ ! -f "$ENV_FILE" ]]; then
  read -p "🔐 Enter GitHub username: " GIT_USERNAME
  read -s -p "🔑 Enter GitHub token: " GIT_TOKEN
  echo
  echo "GIT_USERNAME=$GIT_USERNAME" > "$ENV_FILE"
  echo "GIT_TOKEN=$GIT_TOKEN" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  log "ℹ️ .env file already exists."
fi
source "$ENV_FILE"
if [[ -z "${GIT_USERNAME:-}" || -z "${GIT_TOKEN:-}" ]]; then
  log "❌ Missing GitHub credentials. Exiting."
  exit 1
fi

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CREDENTIALS_FILE"
chmod 600 "$GIT_CREDENTIALS_FILE"
git config --global credential.helper "store --file=$GIT_CREDENTIALS_FILE"
git config --global user.name "$GIT_USERNAME"
log "✅ Git configured."

log "✅ Environment setup completed successfully."
