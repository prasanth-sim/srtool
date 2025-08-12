#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
# The script accepts three parameters:
# 1. BRANCH: The Git branch to checkout (defaults to 'main').
# 2. BASE_DIR: The base directory for all project files.
# 3. CONFIG: The Angular build configuration (e.g., 'production', 'develop', 'uat', 'stg').
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/srtoolbuild}"
CONFIG="${3:-production}"
REPO="srtool-fe"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Derived Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${BRANCH//\//_}_$DATE_TAG.log"
GIT_URL="https://github.com/simaiserver/srtool_fe.git"

# --- Setup Directories ---
mkdir -p "$LOG_DIR" "$BUILD_DIR"

# --- Redirect Output to Log File ---
# All script output will be directed to the console and the log file simultaneously.
exec &> >(tee -a "$LOG_FILE")

echo "🔧 Starting build for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]..."
echo "📅 Timestamp: $DATE_TAG"

# === Git Clone or Pull ===
# This section ensures the repository is present and up-to-date.
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "🚀 Cloning repository from $GIT_URL..."
  git clone "$GIT_URL" "$REPO_DIR"
else
  echo "🔄 Repository already exists. Fetching latest changes..."
  cd "$REPO_DIR"
  git fetch origin
fi

# === Branch Checkout and Update ===
# This is the critical step that checks out the specified branch and gets the latest changes.
cd "$REPO_DIR"
echo "🌐 Attempting to checkout branch [$BRANCH]..."

# Check if the branch exists on the remote before attempting to check it out.
if ! git ls-remote --exit-code origin "$BRANCH" > /dev/null; then
    echo "[❌ ERROR] Remote branch 'origin/$BRANCH' does not exist."
    exit 1
fi

# Check if the branch exists locally (case-insensitive check).
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # If the branch exists locally, check it out and pull the latest changes.
    git checkout "$BRANCH"
    echo "⬇️ Pulling latest changes from origin/$BRANCH..."
    git pull origin "$BRANCH"
else
    # If the branch does not exist locally, create it from the remote branch.
    echo "🆕 Branch '$BRANCH' not found locally. Creating and checking out from 'origin/$BRANCH'..."
    git checkout -b "$BRANCH" "origin/$BRANCH"
fi

# --- Verify Branch Checkout ---
# This check provides explicit confirmation that the desired branch is active.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "$BRANCH" ]]; then
  echo "✅ Successfully checked out branch: $BRANCH"
else
  # This block should no longer be reached with the updated commands, but it's kept as a safeguard.
  echo "⚠️ Warning: The branch checkout may have failed. Current branch is '$CURRENT_BRANCH', but expected '$BRANCH'."
fi

# === Build Process ===
echo "🔨 Building project in: $REPO_DIR"
echo "📦 Installing npm dependencies..."
# The 'npm install' command installs all necessary dependencies.
npm install

# The following 'npm run build' command will output the full command it executes.
# The script's own echo has been simplified to avoid duplication.
echo "🛠️ Starting Angular build..."
npm run build -- --output-path="$BUILD_DIR" --configuration="$CONFIG"

# === Create/Update Symlink ===
# This step creates a symbolic link for easy access to the most recent build.
echo "🔗 Updating 'latest' symlink to point to the new build..."
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
