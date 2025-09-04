#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR
# === Inputs ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build-default}"
ENVIRONMENT="${3:-dev}"
REPO="srtool-fe"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${BRANCH//\//_}_$DATE_TAG.log"
GIT_URL="https://github.com/simaiserver/srtool_fe.git"
mkdir -p "$LOG_DIR" "$BUILD_DIR"
exec &> >(tee -a "$LOG_FILE")
echo "🔧 Starting build for [$REPO] on branch [$BRANCH] for environment [$ENVIRONMENT]..."
echo "📅 Timestamp: $DATE_TAG"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "🚀 Cloning repository from $GIT_URL ..."
  git clone "$GIT_URL" "$REPO_DIR"
fi
echo "🌐 Checking out branch [$BRANCH]..."
cd "$REPO_DIR"
git fetch origin
git reset --hard "origin/$BRANCH"
FRONTEND_DIR="$REPO_DIR"

# Function to add a new environment configuration to angular.json
add_angular_env_config() {
  local env_name="$1"
  local angular_json_file="$2"
  echo "Adding configuration for '$env_name' to angular.json..."
  local temp_config_file=$(mktemp)
  cat > "$temp_config_file" <<EOF
           "${env_name}": {
             "fileReplacements": [
               {
                 "replace": "src/environments/environment.ts",
                 "with": "src/environments/environment.${env_name}.ts"
               }
             ]
           },
EOF
  # Use sed's 'r' command to read and insert the content of the temporary file.
  sed -i "/\"configurations\": {/r $temp_config_file" "$angular_json_file"
  rm "$temp_config_file"
  echo "✅ Configuration added."
}

# Environment creation logic must be done after git reset
case "$ENVIRONMENT" in
  "development" | "production" | "uat" | "staging")
    echo "Using existing environment: $ENVIRONMENT"
    ;;
  *)
    FRONTEND_ENV_DIR="$REPO_DIR/src/environments"
    NEW_ENV_FILE="$FRONTEND_ENV_DIR/environment.$ENVIRONMENT.ts"
    ANGULAR_JSON_FILE="$REPO_DIR/angular.json"
    # New logic: Remove existing file to ensure a clean slate
    if [ -f "$NEW_ENV_FILE" ]; then
      echo "Removing old environment file: $NEW_ENV_FILE"
      rm "$NEW_ENV_FILE"
    fi

    echo "Creating new comprehensive environment file: $NEW_ENV_FILE"
    cat > "$NEW_ENV_FILE" << EOF
export const environment = {
  production: true,
  loginUrl: '/login',
  url: 'https://cisr.${ENVIRONMENT}.simadvisory.com',
  API_URL: \`/app\`,
  ACCESS_API_URL: 'https://cisr.${ENVIRONMENT}.simadvisory.com/app',
  KeycloakUrl: 'https://auth.dev.simadvisory.com/auth',
  Realm: 'SRT_${ENVIRONMENT^^}',
  ClientId: 'D_SRT_Client',

  KEYCLOAK_EXTRA_ARGS_PREPENDED:
    '--spi-login-protocol-openid-connect-legacy-logout-redirect-uri=true',
  version: 'YTD - Oct 2024',
  version1: 'YTD - Sept 2024',
  version2: 'YTD - Oct 2024',
  version3: 'YTD - Oct 2024',
  version4: 'YTD - Sept 2024',
  version5: 'YTD - Oct 2024',
  meritorDateOfUpdate: 'Oct 2024',

  feedBackSubject: 'Feedback',
  toName: 'Praveen',

  NX_SUPERSET_DOMAIN: "https://reports.cisr.${ENVIRONMENT}.alpha.simadvisory.com",
  NX_API_USER_ACCESS_URL: "https://cisr.${ENVIRONMENT}.alpha.simadvisory.com/api/v1/user-access/reports/token",
  ID: "5600ea30-7e61-4e3d-957b-909a84ddc68b",
};
EOF
    echo "✅ Created new environment file: $NEW_ENV_FILE"

    if ! grep -q "\"$ENVIRONMENT\"" "$ANGULAR_JSON_FILE"; then
      add_angular_env_config "$ENVIRONMENT" "$ANGULAR_JSON_FILE"
    else
      echo "⚠️ Configuration '$ENVIRONMENT' already exists in angular.json."
    fi
    ;;
esac

echo "🔨 Building project in: $FRONTEND_DIR"
echo "📦 Installing npm dependencies..."
npm install
echo "🛠️ Running Angular build for the [$ENVIRONMENT] environment..."
ng build --configuration="$ENVIRONMENT" --output-path="$BUILD_DIR"
ln -snf "$BUILD_DIR" "$LATEST_LINK"
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
