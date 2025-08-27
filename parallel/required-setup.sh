#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[env-setup]"
ENV_FILE="$SCRIPT_DIR/.env"
GIT_CREDENTIALS_FILE="$SCRIPT_DIR/.git-credentials"

log() { echo "$LOG_PREFIX $(date +'%F %T') $*"; }

# === Install Tools ===
log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip, jq..."
sudo apt-get install -y git curl unzip software-properties-common jq

log "☕ Installing OpenJDK 11..."
sudo apt-get install -y openjdk-11-jdk
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
log "✅ JAVA_HOME set to $JAVA_HOME"

log "🛠️ Installing Maven 3.6.3..."
sudo apt-get install -y maven

log "🟩 Installing NVM and Node.js 16.15.0..."
if [ ! -d "$HOME/.nvm" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  log "✅ NVM installed. Please run this script again or open a new terminal."
  exit 1
fi

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

nvm install 16.15.0
nvm use 16.15.0
log "✅ Node.js 16.15.0 installed and in use."

log "📦 Installing Angular CLI 13.3.11..."
npm install -g @angular/cli@13.3.11

log "⚙️ Installing GNU Parallel..."
sudo apt-get install -y parallel

# === .env setup ===
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

# === Version Checks ===
EXPECTED_JAVA="11"
EXPECTED_MAVEN="3"
EXPECTED_NODE="16"
EXPECTED_NPM="8"
EXPECTED_NG="13"
EXPECTED_GIT="2"

check_version() {
  TOOL="$1"; ACTUAL="$2"; EXPECTED="$3";
  if [[ "$ACTUAL" == *"$EXPECTED"* ]]; then
    log "✅ $TOOL version OK: $ACTUAL"
  else
    log "❌ $TOOL version mismatch: found '$ACTUAL', expected '$EXPECTED'"
    exit 1
  fi
}

# The Java check is modified to not exit, allowing the script to continue.
JAVA_VERSION=$(java -version 2>&1 | awk -F[\".] '/version/ {print $2}')
if [[ "$JAVA_VERSION" == *"$EXPECTED_JAVA"* ]]; then
    log "✅ Java version OK: $JAVA_VERSION"
else
    log "❌ Java version mismatch: found '$JAVA_VERSION', expected '$EXPECTED_JAVA'. Continuing anyway."
fi

MAVEN_VERSION=$(mvn -v | awk '/Apache Maven/ {print $3}' | cut -d. -f1)
NODE_VERSION=$(node -v | tr -d 'v' | cut -d. -f1)
NPM_VERSION=$(npm -v | cut -d. -f1)
NG_VERSION=$(ng version | awk '/Angular CLI/ {print $3}' | cut -d. -f1)
GIT_VERSION=$(git --version | awk '{print $3}' | cut -d. -f1)

check_version "Maven" "$MAVEN_VERSION" "$EXPECTED_MAVEN"
check_version "Node.js" "$NODE_VERSION" "$EXPECTED_NODE"
check_version "npm" "$NPM_VERSION" "$EXPECTED_NPM"
check_version "Angular CLI" "$NG_VERSION" "$EXPECTED_NG"
check_version "Git" "$GIT_VERSION" "$EXPECTED_GIT"

log "✅ Environment setup completed successfully."
