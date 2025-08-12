#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build-default}"
REPO="srtool-be"
GIT_URL="https://github.com/simaiserver/srtool_be.git"
# Corrected ARTIFACT_PATH to be relative to the salesrealization directory
ARTIFACT_PATH="target/salesrealization-0.0.1-SNAPSHOT.jar"
BUILD_CMD="mvn clean install -Dmaven.test.skip=true"

DATE_TAG=$(date +"%Y%m%d_%H%M%S")
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${BRANCH//\//_}_$DATE_TAG.log"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")

echo "🔧 Building [$REPO] on branch [$BRANCH]..."

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "🚀 Cloning repository..."
  git clone "$GIT_URL" "$REPO_DIR"
fi
git -C "$REPO_DIR" fetch origin
git -C "$REPO_DIR" checkout "$BRANCH"
git -C "$REPO_DIR" reset --hard "origin/$BRANCH"

# --- FIX: Change directory to the correct sub-directory containing pom.xml ---
echo "📁 Changing to project directory: $REPO_DIR/salesrealization"
cd "$REPO_DIR/salesrealization"

echo "🔨 Running Maven build: $BUILD_CMD"
if ! eval "$BUILD_CMD"; then
  echo "❌ Maven build failed. Exiting."
  exit 1
fi

STATUS="FAIL"
if [[ -f "$ARTIFACT_PATH" ]]; then
  cp -p "$ARTIFACT_PATH" "$BUILD_DIR/"
  ln -snf "$BUILD_DIR" "$LATEST_LINK"
  STATUS="SUCCESS"
  echo "✅ Artifact copied to: $BUILD_DIR"
else
  echo "⚠️ Artifact not found at $ARTIFACT_PATH. This should not happen if the Maven build succeeded."
  exit 1
fi

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "✅ Build complete with status: $STATUS"
