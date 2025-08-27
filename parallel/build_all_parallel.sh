#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# This script may fail with a "syntax error" on Linux if it was created/edited on a Windows system.
# To fix this, run `sed -i 's/\r$//' ./build_all_parallel.sh` in your terminal before execution.

# Check if the script is running in Bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires Bash to run. Please execute it with 'bash ./build_all_parallel.sh'." >&2
    exit 1
fi

CONFIG_FILE="$HOME/.repo_builder_config"

# === Save config ===
# This function saves all your choices (base directory, selected repos, branches, and environments)
# so they can be loaded as defaults the next time you run the script.
save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    # Overwrite the config file with the base directory and selected repos.
    echo "BASE_INPUT=$BASE_INPUT" > "$CONFIG_FILE"
    echo "SELECTED_REPOS=${SELECTED[*]}" >> "$CONFIG_FILE"

    # Loop through the branch choices and append them to the config file.
    for repo in "${!BRANCH_CHOICES[@]}"; do
        local var_name="BRANCH_${repo//-/_}"
        echo "$var_name=${BRANCH_CHOICES[$repo]}" >> "$CONFIG_FILE"
    done

    # Loop through the environment choices and append them.
    for repo in "${!ENVIRONMENT_CHOICES[@]}"; do
        local var_name="ENVIRONMENT_${repo//_/-}"
        echo "$var_name=${ENVIRONMENT_CHOICES[$repo]}" >> "$CONFIG_FILE"
    done

    echo "Configuration saved."
}

# === Load config ===
# This function loads the configuration from the previous run.
load_config() {
    declare -g BASE_INPUT=""
    declare -g SELECTED=()
    declare -gA BRANCH_CHOICES
    declare -gA ENVIRONMENT_CHOICES

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "💡 Loading previous inputs from $CONFIG_FILE..."
        while IFS='=' read -r key value; do
            case "$key" in
                BASE_INPUT) BASE_INPUT="$value" ;;
                SELECTED_REPOS) IFS=' ' read -r -a SELECTED <<< "$value" ;;
                BRANCH_*)
                    local repo_key="${key#BRANCH_}"
                    local repo_name="${repo_key//_/-}"
                    BRANCH_CHOICES["$repo_name"]="$value"
                    ;;
                ENVIRONMENT_*)
                    local repo_key="${key#ENVIRONMENT_}"
                    local repo_name="${repo_key//_/-}"
                    ENVIRONMENT_CHOICES["$repo_name"]="$value"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

# Load previous config
load_config

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"

# Optional setup
if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT' to set up the environment? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then
        echo "Running required-setup.sh..."
        source "$REQUIRED_SETUP_SCRIPT"
    else
        echo "Skipping required-setup.sh."
    fi
else
    echo "⚠️ Warning: required-setup.sh not found."
fi

# Base directory
DEFAULT_BASE_INPUT="${BASE_INPUT:-build}"
read -rp "📁 Enter base directory (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}"
BASE_DIR="$HOME/$BASE_INPUT"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"

mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

# Repo definitions
declare -A REPO_URLS=(
    ["srtool-be"]="https://github.com/simaiserver/srtool_be.git"
    ["srtool-fe"]="https://github.com/simaiserver/srtool_fe.git"
)
declare -A DEFAULT_BRANCHES=(
    ["srtool-be"]="main"
    ["srtool-fe"]="main"
)
REPOS=("srtool-be" "srtool-fe")
BUILD_SCRIPTS=(
    "$SCRIPT_DIR/build_srtool_be.sh"
    "$SCRIPT_DIR/build_srtool_fe.sh"
)

# Build function
build_and_log_repo() {
    local repo_name="$1"
    local script_path="$2"
    local log_file="$3"
    local tracker_file="$4"
    local base_dir_for_build_script="$5"
    local branch="$6"
    local environment="$7"

    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $repo_name ---" >> "$log_file"

    set +e
    if script_output=$("${script_path}" "$branch" "$base_dir_for_build_script" "$environment" 2>&1); then
        script_exit_code=0
    else
        script_exit_code=$?
    fi
    set -e

    echo "$script_output" | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') $line"
    done >> "$log_file"

    local status="FAIL"
    if [[ "$script_exit_code" -eq 0 ]]; then
        status="SUCCESS"
    fi
    echo "${repo_name},${status},${log_file}" >> "$tracker_file"
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $repo_name with status: $status ---" >> "$log_file"
}
export -f build_and_log_repo

# === Phase 1 & 2: Prepare repos and collect inputs ===
COMMANDS=()
declare -A SELECTED_REPOS_MAP
echo "📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
    echo "  $((i+1))) ${REPOS[$i]}"
done
echo "  0) ALL"

# Find the default selection based on the previously selected repos.
# If nothing was selected before, default to "ALL" (0).
if [[ ${#SELECTED[@]} -gt 0 ]]; then
    # Find the index of the first previously selected repo.
    DEFAULT_REPO_INDEX=-1
    for i in "${!REPOS[@]}"; do
        if [[ "${REPOS[$i]}" == "${SELECTED[0]}" ]]; then
            DEFAULT_REPO_INDEX=$i
            break
        fi
    done

    if [[ "$DEFAULT_REPO_INDEX" -ne -1 ]]; then
        DEFAULT_REPO_SELECTION=$((DEFAULT_REPO_INDEX + 1))
    else
        # If the old selection is not in the list, default to ALL.
        DEFAULT_REPO_SELECTION=0
    fi
else
    # Default to "ALL" if no previous selection was found.
    DEFAULT_REPO_SELECTION=0
fi
read -rp "Enter the number of the repository to build [default: $DEFAULT_REPO_SELECTION]: " USER_REPO_SELECTION
REPO_SELECTION="${USER_REPO_SELECTION:-$DEFAULT_REPO_SELECTION}"


case "$REPO_SELECTION" in
    "0")
        for repo in "${REPOS[@]}"; do
            SELECTED_REPOS_MAP["$repo"]=1
        done
        ;;
    [1-"${#REPOS[@]}"])
        REPO_INDEX=$((REPO_SELECTION-1))
        repo_name_to_process="${REPOS[$REPO_INDEX]}"
        SELECTED_REPOS_MAP["$repo_name_to_process"]=1
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

# Prepare and collect inputs for selected repos
for repo_name_to_process in "${!SELECTED_REPOS_MAP[@]}"; do
    i=-1
    for j in "${!REPOS[@]}"; do
        if [[ "${REPOS[$j]}" == "$repo_name_to_process" ]]; then
            i=$j
            break
        fi
    done
    [[ "$i" -eq -1 ]] && continue

    REPO="${REPOS[$i]}"
    REPO_DIR="$CLONE_DIR/$REPO"
    DEFAULT_REPO_BRANCH="${DEFAULT_BRANCHES[$REPO]}"

    CURRENT_BRANCH="${BRANCH_CHOICES[$REPO]:-${DEFAULT_BRANCHES[$REPO]}}"

    echo -e "\n🚀 Checking '$REPO' repository..."
    if [[ -d "$REPO_DIR/.git" ]]; then
        echo "🔄 Updating $REPO..."
        (cd "$REPO_DIR" && git fetch origin --prune && git reset --hard HEAD && git clean -fd && git checkout -B "$DEFAULT_REPO_BRANCH" origin/"$DEFAULT_REPO_BRANCH") \
        || { echo "❌ Failed to prepare $REPO. Skipping."; unset SELECTED_REPOS_MAP["$REPO"]; continue; }
    else
        echo "📥 Cloning ${REPO_URLS[$REPO]}"
        git clone "${REPO_URLS[$REPO]}" "$REPO_DIR" \
        || { echo "❌ Failed to clone $REPO. Skipping."; unset SELECTED_REPOS_MAP["$REPO"]; continue; }
    fi

    # First, get the branch input from the user
    read -rp "Enter branch for $REPO [default: $CURRENT_BRANCH]: " USER_BRANCH
    BRANCH_CHOICES["$REPO"]="${USER_BRANCH:-$CURRENT_BRANCH}"

    # Now, check the chosen branch and offer a constrained environment list if needed
    if [[ "$REPO" == "srtool-fe" ]]; then
        # Check if the chosen branch is 'feature/env_only'
        if [[ "${BRANCH_CHOICES["$REPO"]}" == "feature/env_only" ]]; then
            DEFAULT_ENV="uat"
            echo "📦 Available Environments (for branch 'feature/env_only' only):"
            echo "  1) uat"
            read -rp "Enter the number for the environment [default: 1]: " USER_ENV_SELECTION
            ENV_SELECTION="${USER_ENV_SELECTION:-1}"

            # Map user input to the single allowed environment
            case "$ENV_SELECTION" in
                "1")
                    ENVIRONMENT_CHOICES["$REPO"]="uat"
                    ;;
                *)
                    echo "Invalid selection. Only 'uat' is allowed for this branch. Defaulting to 'uat'."
                    ENVIRONMENT_CHOICES["$REPO"]="uat"
                    ;;
            esac
        else
            # For all other branches, show the full list of environments
            DEFAULT_ENV="${ENVIRONMENT_CHOICES["$REPO"]:-"production"}"
            DEFAULT_ENV_SELECTION=""
            case "$DEFAULT_ENV" in
                "development") DEFAULT_ENV_SELECTION=1 ;;
                "production") DEFAULT_ENV_SELECTION=2 ;;
                "uat") DEFAULT_ENV_SELECTION=3 ;;
                "staging") DEFAULT_ENV_SELECTION=4 ;;
                *) DEFAULT_ENV_SELECTION=2 ;; # Fallback to production if last saved is invalid
            esac

            echo "📦 Available Environments:"
            echo "  1) development"
            echo "  2) production"
            echo "  3) uat"
            echo "  4) staging"
            echo "  5) new env"
            read -rp "Enter the number for the environment [default: $DEFAULT_ENV_SELECTION]: " USER_ENV_SELECTION
            ENV_SELECTION="${USER_ENV_SELECTION:-$DEFAULT_ENV_SELECTION}"

            # Map user input to Angular environment configurations
            case "$ENV_SELECTION" in
                "1")
                    ENVIRONMENT_CHOICES["$REPO"]="development"
                    ;;
                "2")
                    ENVIRONMENT_CHOICES["$REPO"]="production"
                    ;;
                "3")
                    ENVIRONMENT_CHOICES["$REPO"]="uat"
                    ;;
                "4")
                    ENVIRONMENT_CHOICES["$REPO"]="staging"
                    ;;
                "5")
                    read -rp "Enter the name for the new custom environment: " CUSTOM_ENV
                    ENVIRONMENT_CHOICES["$REPO"]="$CUSTOM_ENV"

                    FRONTEND_ENV_DIR="$CLONE_DIR/$REPO/src/environments"
                    NEW_ENV_FILE="$FRONTEND_ENV_DIR/environment.$CUSTOM_ENV.ts"
                    ANGULAR_JSON_FILE="$CLONE_DIR/$REPO/angular.json"

                    if [ ! -f "$NEW_ENV_FILE" ]; then
                      cp "$FRONTEND_ENV_DIR/environment.ts" "$NEW_ENV_FILE"
                      echo "✅ Created new environment file: $NEW_ENV_FILE"
                    else
                      echo "⚠️ Environment file already exists: $NEW_ENV_FILE"
                    fi

                    # Check if 'jq' is installed for reliable JSON manipulation
                    if command -v jq &>/dev/null; then
                      echo "📝 Adding new configuration '$CUSTOM_ENV' to angular.json using jq..."
                      TEMP_JSON=$(mktemp)
                      jq --arg envName "$CUSTOM_ENV" \
                        '.projects."srtool-fe".architect.build.configurations |= . + {
                          ($envName): {
                            "fileReplacements": [
                              {
                                "replace": "src/environments/environment.ts",
                                "with": "src/environments/environment." + $envName + ".ts"
                              }
                            ]
                          }
                        }' "$ANGULAR_JSON_FILE" > "$TEMP_JSON" && mv "$TEMP_JSON" "$ANGULAR_JSON_FILE"
                      echo "✅ Added configuration '$CUSTOM_ENV' to angular.json."
                    else
                      echo "⚠️ 'jq' is not installed. Falling back to sed. This might be brittle."
                      # Add the new configuration to angular.json if it doesn't exist
                      if ! grep -q "\"$CUSTOM_ENV\"" "$ANGULAR_JSON_FILE"; then
                        echo "📝 Adding new configuration '$CUSTOM_ENV' to angular.json..."
                        # Use sed to add the new configuration entry
                        sed -i.bak '/"production": {/a \
                            "'"$CUSTOM_ENV"'": {\
                              "fileReplacements": [\
                                {\
                                  "replace": "src/environments/environment.ts",\
                                  "with": "src/environments/environment.'"$CUSTOM_ENV"'.ts"\
                                }\
                              ]\
                            },' "$ANGULAR_JSON_FILE"
                        rm "$ANGULAR_JSON_FILE.bak"
                        echo "✅ Added configuration '$CUSTOM_ENV' to angular.json."
                      else
                        echo "⚠️ Configuration '$CUSTOM_ENV' already exists in angular.json."
                      fi
                    fi
                    ;;
                *)
                    echo "Invalid selection. Defaulting to '$DEFAULT_ENV'."
                    ENVIRONMENT_CHOICES["$REPO"]="$DEFAULT_ENV"
                    ;;
            esac
        fi
    else
        # For non-frontend repos, just use a default value without prompting
        ENVIRONMENT_CHOICES["$REPO"]="default"
    fi

    LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
    COMMANDS+=("build_and_log_repo \"$REPO\" \"${BUILD_SCRIPTS[$i]}\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"${BRANCH_CHOICES[$REPO]}\" \"${ENVIRONMENT_CHOICES[$REPO]}\"")
done

# Update the SELECTED array based on the current run's choices
SELECTED=()
for repo in "${!SELECTED_REPOS_MAP[@]}"; do
    SELECTED+=("$repo")
done

# Save config
save_config

# === Phase 3: Parallel execution ===
CPU_CORES=$(nproc)
# Calculate max jobs = 80% of available cores (rounded up)
MAX_JOBS=$(( (CPU_CORES * 80 + 99) / 100 ))

echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel, limited to ~80% of CPU capacity..."

if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No parallel commands to execute. Exiting."
    exit 0
fi

set +e # Temporarily disable 'exit on error' for the parallel command
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$MAX_JOBS" --load 80% --no-notice --bar
PARALLEL_EXIT_CODE=$?
set -e # Re-enable 'exit on error'

# === Phase 4: Summary ===
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
SUMMARY_CSV_FILE="$LOG_DIR/build-summary-${DATE_TAG}.csv"

if [[ -f "$TRACKER_FILE" ]]; then
    echo "Script Start Time,$START_TIME" > "$SUMMARY_CSV_FILE"
    echo "Script End Time,$END_TIME" >> "$SUMMARY_CSV_FILE"
    echo "---" >> "$SUMMARY_CSV_FILE"
    echo "Status,Repository,Log File" >> "$SUMMARY_CSV_FILE"
    while IFS=',' read -r REPO STATUS LOGFILE; do
        [[ "$STATUS" == "SUCCESS" ]] && echo "[✔️ DONE] $REPO - see log: $LOGFILE" || echo "[❌ FAIL] $REPO - see log: $LOGFILE"
        echo "$STATUS,$REPO,$LOGFILE" >> "$SUMMARY_CSV_FILE"
    done < "$TRACKER_FILE"
else
    echo "⚠️ No tracker file found."
fi

echo "📄 Summary at: $SUMMARY_CSV_FILE"
exit $PARALLEL_EXIT_CODE
