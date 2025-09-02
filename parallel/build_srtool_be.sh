#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build-default}"
REPO="srtool-be"
GIT_URL="https://github.com/simaiserver/srtool_be.git"
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

echo "🌐 Fetching remote branches..."
git -C "$REPO_DIR" fetch origin --prune

if git -C "$REPO_DIR" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git -C "$REPO_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
else
    echo "❌ Branch '$BRANCH' does not exist on remote. Exiting."
    exit 1
fi

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
  echo "⚠️ Artifact not found at $ARTIFACT_PATH despite build success."
  exit 1
fi

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "✅ Build complete with status: $STATUS"
