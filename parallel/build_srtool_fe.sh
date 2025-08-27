#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
# The branch to checkout, defaults to 'main' if not provided
BRANCH="${1:-main}"
# The base directory for all operations, defaults to '$HOME/build-default'
BASE_DIR="${2:-$HOME/build-default}"
# The environment to build for, defaults to 'dev' if not provided
ENVIRONMENT="${3:-dev}"

REPO="srtool-fe"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Derived Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${BRANCH//\//_}_$DATE_TAG.log"
GIT_URL="https://github.com/simaiserver/srtool_fe.git"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

# Redirect all script output to both stdout and the log file
exec &> >(tee -a "$LOG_FILE")

echo "🔧 Starting build for [$REPO] on branch [$BRANCH] for environment [$ENVIRONMENT]..."
echo "📅 Timestamp: $DATE_TAG"

# === Git Clone or Pull ===
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "🚀 Cloning repository from $GIT_URL ..."
  git clone "$GIT_URL" "$REPO_DIR"
fi

echo "🌐 Checking out branch [$BRANCH]..."
# Change to the repository directory to ensure git commands run correctly
cd "$REPO_DIR"
git fetch origin
git reset --hard "origin/$BRANCH"

# === FIX: Use the repository root as the frontend project directory ===
# The 'll' output shows the project files are in the repository's root.
FRONTEND_DIR="$REPO_DIR"

echo "🔨 Building project in: $FRONTEND_DIR"
# The 'cd' command is not needed here as we are already in the correct directory.
# We will just proceed with the npm commands.

echo "📦 Installing npm dependencies..."
npm install

echo "🛠️ Running Angular build for the [$ENVIRONMENT] environment..."
# Use the --configuration flag to select the correct environment file
npm run build -- --configuration="$ENVIRONMENT" --output-path="$BUILD_DIR"

ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
