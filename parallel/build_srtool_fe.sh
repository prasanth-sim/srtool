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
echo "🔨 Building project in: $FRONTEND_DIR"
echo "📦 Installing npm dependencies..."
npm install
echo "🛠️ Running Angular build for the [$ENVIRONMENT] environment..."
ng build --configuration="$ENVIRONMENT" --output-path="$BUILD_DIR"
ln -snf "$BUILD_DIR" "$LATEST_LINK"
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
