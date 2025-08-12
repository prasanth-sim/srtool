#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# Check if the script is running in Bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires Bash to run. Please execute it with 'bash ./build_all_parallel.sh'." >&2
    exit 1
fi

CONFIG_FILE="$HOME/.repo_builder_config"

# === Save config ===
# This function saves all your choices (base directory, selected repos, branches, and configs)
# so they can be loaded as defaults the next time you run the script.
save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    # Overwrite the config file with the base directory and selected repos.
    echo "BASE_INPUT=$BASE_INPUT" > "$CONFIG_FILE"
    # Join the selected repos into a single string for storage
    printf "SELECTED_REPOS=%s\n" "${SELECTED[*]}" >> "$CONFIG_FILE"

    # Loop through the branch choices and append them to the config file.
    for repo in "${!BRANCH_CHOICES[@]}"; do
        local var_name="BRANCH_${repo//-/_}"
        echo "$var_name=${BRANCH_CHOICES[$repo]}" >> "$CONFIG_FILE"
    done
    # Loop through the config choices and append them to the config file.
    for repo in "${!CONFIG_CHOICES[@]}"; do
        local var_name="CONFIG_${repo//-/_}"
        echo "$var_name=${CONFIG_CHOICES[$repo]}" >> "$CONFIG_FILE"
    done
    echo "Configuration saved."
}

# === Load config (CORRECTED) ===
# This function loads the configuration from the previous run.
load_config() {
    declare -g BASE_INPUT=""
    declare -g SELECTED=()
    declare -gA BRANCH_CHOICES
    declare -gA CONFIG_CHOICES
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "💡 Loading previous inputs from $CONFIG_FILE..."
        # Read the file line by line using a standard while loop
        while IFS='=' read -r key value; do
            case "$key" in
                BASE_INPUT) BASE_INPUT="$value" ;;
                SELECTED_REPOS) IFS=' ' read -r -a SELECTED <<< "$value" ;;
                BRANCH_*)
                    local repo_key="${key#BRANCH_}"
                    local repo_name="${repo_key//_/-}"
                    BRANCH_CHOICES["$repo_name"]="$value"
                    ;;
                CONFIG_*)
                    local repo_key="${key#CONFIG_}"
                    local repo_name="${repo_key//_/-}"
                    CONFIG_CHOICES["$repo_name"]="$value"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

load_config

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"

if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT'? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then
        if [[ -x "$REQUIRED_SETUP_SCRIPT" ]]; then
            "$REQUIRED_SETUP_SCRIPT"
        else
            echo "❌ Error: '$REQUIRED_SETUP_SCRIPT' is not executable. Skipping." >&2
        fi
    else
        echo "Skipping required-setup.sh."
    fi
else
    echo "⚠️ Warning: required-setup.sh not found."
fi

DEFAULT_BASE_INPUT="${BASE_INPUT:-srtool1}"
read -rp "📁 Enter base directory (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}"
BASE_DIR="$HOME/$BASE_INPUT"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"

mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

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
declare -a AVAILABLE_CONFIGS=("develop" "production" "uat" "stg")

echo -e "\n📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

DEFAULT_SELECTION_NUMBERS=""
if [ "${#SELECTED[@]}" -gt 0 ]; then
    for repo_name in "${SELECTED[@]}"; do
        for i in "${!REPOS[@]}"; do
            if [[ "${REPOS[$i]}" == "$repo_name" ]]; then
                DEFAULT_SELECTION_NUMBERS+="$((i+1)) "
                break
            fi
        done
    done
    DEFAULT_SELECTION_NUMBERS="${DEFAULT_SELECTION_NUMBERS% }"
fi

read -rp $'\n📌 Enter repo numbers (space-separated or 0 for all) [default: '"${DEFAULT_SELECTION_NUMBERS:-0}"']: ' -a USER_SELECTED_INPUT

if [[ -z "${USER_SELECTED_INPUT[*]}" ]]; then
    if [ -n "$DEFAULT_SELECTION_NUMBERS" ]; then
        IFS=' ' read -r -a USER_SELECTED_INPUT <<< "$DEFAULT_SELECTION_NUMBERS"
    else
        USER_SELECTED_INPUT=("0")
    fi
fi

SELECTED=()
if [[ "${USER_SELECTED_INPUT[0]}" == "0" ]]; then
    SELECTED=("${REPOS[@]}")
else
    for idx_str in "${USER_SELECTED_INPUT[@]}"; do
        idx="$idx_str"
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
            echo "⚠️ Invalid selection: $idx. Skipping..."
            continue
        fi
        i=$((idx - 1))
        SELECTED+=("${REPOS[$i]}")
    done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "No valid repositories selected. Exiting."
    exit 0
fi

# === Build function (MODIFIED) ===
build_and_log_repo() {
    local repo_name="$1"
    local script_path="$2"
    local log_file="$3"
    local tracker_file="$4"
    local base_dir_for_build_script="$5"
    local branch="$6"
    local config="$7"

    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $repo_name ---" >> "$log_file"

    set +e
    if script_output=$("${script_path}" "$branch" "$base_dir_for_build_script" "$config" 2>&1); then
        script_exit_code=0
    else
        script_exit_code=$?
    fi
    set -e

    echo "$script_output" | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%m %H:%M:%S') $line"
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
declare -a repos_to_process
for i in "${!SELECTED[@]}"; do
    REPO="${SELECTED[$i]}"

    SCRIPT_TO_RUN=""
    for j in "${!REPOS[@]}"; do
        if [[ "${REPOS[$j]}" == "$REPO" ]]; then
            SCRIPT_TO_RUN="${BUILD_SCRIPTS[$j]}"
            break
        fi
    done

    [[ -z "$SCRIPT_TO_RUN" ]] && continue

    REPO_DIR="$CLONE_DIR/$REPO"
    DEFAULT_REPO_BRANCH="${DEFAULT_BRANCHES[$REPO]}"

    CURRENT_BRANCH="${BRANCH_CHOICES[$REPO]:-${DEFAULT_BRANCHES[$REPO]}}"
    DEFAULT_CONFIG_NAME="${AVAILABLE_CONFIGS[0]}"
    CURRENT_CONFIG="${CONFIG_CHOICES[$REPO]:-${DEFAULT_CONFIG_NAME}}"

    echo -e "\n🚀 Checking '$REPO' repository..."
    if [[ -d "$REPO_DIR/.git" ]]; then
        echo "🔄 Updating $REPO..."
        (cd "$REPO_DIR" && git fetch origin --prune && git reset --hard HEAD && git clean -fd && git checkout -B "$DEFAULT_REPO_BRANCH" "origin/$DEFAULT_REPO_BRANCH") \
        || { echo "❌ Failed to prepare $REPO. Skipping."; continue; }
    else
        echo "📥 Cloning ${REPO_URLS[$REPO]}"
        git clone "${REPO_URLS[$REPO]}" "$REPO_DIR" \
        || { echo "❌ Failed to clone $REPO. Skipping."; continue; }
    fi

    # Prompt for branch for all repos
    read -rp "Enter branch for $REPO [default: $CURRENT_BRANCH]: " USER_BRANCH
    BRANCH_CHOICES["$REPO"]="${USER_BRANCH:-$CURRENT_BRANCH}"

    # Prompt for config ONLY for srtool-fe, now with number selection
    if [[ "$REPO" == "srtool-fe" ]]; then
        echo -e "\n⚙️ Available build configurations for $REPO:"
        for k in "${!AVAILABLE_CONFIGS[@]}"; do
            printf "  %d) %s\n" "$((k+1))" "${AVAILABLE_CONFIGS[$k]}"
        done
        CONFIG_CHOICE_NUM=
        read -rp "📌 Enter configuration number [default: 1]: " USER_CONFIG_CHOICE_NUM
        USER_CONFIG_CHOICE_NUM="${USER_CONFIG_CHOICE_NUM:-1}"

        # Validate user input
        if [[ "$USER_CONFIG_CHOICE_NUM" =~ ^[0-9]+$ ]] && (( USER_CONFIG_CHOICE_NUM > 0 && USER_CONFIG_CHOICE_NUM <= ${#AVAILABLE_CONFIGS[@]} )); then
            CONFIG_CHOICES["$REPO"]="${AVAILABLE_CONFIGS[$((USER_CONFIG_CHOICE_NUM-1))]}"
        else
            echo "⚠️ Invalid selection: $USER_CONFIG_CHOICE_NUM. Defaulting to '${DEFAULT_CONFIG_NAME}'."
            CONFIG_CHOICES["$REPO"]="${DEFAULT_CONFIG_NAME}"
        fi
    else
        # Set default config for other repos
        CONFIG_CHOICES["$REPO"]="${CURRENT_CONFIG}"
    fi

    LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
    # The command is the same, using the chosen or default config
    COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT_TO_RUN\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"${BRANCH_CHOICES[$REPO]}\" \"${CONFIG_CHOICES[$REPO]}\"")
done

save_config

# === Phase 3: Parallel execution ===
CPU_CORES=$(nproc)
if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No builds to run."
    exit 0
fi

printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --load 100% --no-notice --bar
PARALLEL_EXIT_CODE=$?

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
