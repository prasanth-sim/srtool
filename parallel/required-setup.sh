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

log "📦 Installing Git, curl, unzip..."
sudo apt-get install -y git curl unzip software-properties-common

log "☕ Installing OpenJDK 11..."
sudo apt-get install -y openjdk-11-jdk

log "🛠️ Installing Maven 3.6.3..."
sudo apt-get install -y maven

log "🟩 Installing Node.js 16.15.0 and npm 8.5.5..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g npm@8.5.5

log "📦 Installing Angular CLI 13.3.11..."
sudo npm install -g @angular/cli@13.3.11

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
  log "❌ Missing GitHub credentials."
  exit 1
fi

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CREDENTIALS_FILE"
chmod 600 "$GIT_CREDENTIALS_FILE"
git config --global credential.helper "store --file=$GIT_CREDENTIALS_FILE"
git config --global user.name "$GIT_USERNAME"
log "✅ Git configured."

# === Version Checks ===
EXPECTED_JAVA="11"
EXPECTED_MAVEN="3.6.3"
EXPECTED_NODE="16.15.0"
EXPECTED_NPM="8.5.5"
EXPECTED_NG="13.3.11"
EXPECTED_GIT="2"
EXPECTED_PARALLEL="2020"

check_version() {
  TOOL="$1"; ACTUAL="$2"; EXPECTED="$3"
  if [[ "$ACTUAL" == *"$EXPECTED"* ]]; then
    log "✅ $TOOL version OK: $ACTUAL"
  else
    log "❌ $TOOL version mismatch: found '$ACTUAL', expected '$EXPECTED'"
    exit 1
  fi
}

JAVA_VERSION=$(java -version 2>&1 | awk -F[\".] '/version/ {print $2}')
MAVEN_VERSION=$(mvn -v | awk '/Apache Maven/ {print $3}')
NODE_VERSION=$(node -v | tr -d 'v')
NPM_VERSION=$(npm -v)
NG_VERSION=$(ng version | awk '/Angular CLI/ {print $3}')
GIT_VERSION=$(git --version | awk '{print $3}' | cut -d. -f1)
PARALLEL_VERSION=$(parallel --version | head -n 1 | awk '{print $3}')

check_version "Java" "$JAVA_VERSION" "$EXPECTED_JAVA"
check_version "Maven" "$MAVEN_VERSION" "$EXPECTED_MAVEN"
check_version "Node.js" "$NODE_VERSION" "$EXPECTED_NODE"
check_version "npm" "$NPM_VERSION" "$EXPECTED_NPM"
check_version "Angular CLI" "$NG_VERSION" "$EXPECTED_NG"
check_version "Git" "$GIT_VERSION" "$EXPECTED_GIT"
check_version "GNU Parallel" "$PARALLEL_VERSION" "$EXPECTED_PARALLEL"

log "✅ Environment setup completed successfully."
