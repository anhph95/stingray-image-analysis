#!/usr/bin/env bash
###############################################################################
# Run Ultralytics YOLO training locally or from a Prefect shell task.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

CONFIG_PATH="${1:-}"
if [[ -z "$CONFIG_PATH" ]]; then
    echo "[ERROR] Provide a training configuration file." >&2
    exit 2
fi
if [[ "$CONFIG_PATH" != /* ]]; then
    CONFIG_PATH="$SCRIPT_DIR/$CONFIG_PATH"
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "[ERROR] Configuration does not exist: $CONFIG_PATH" >&2
    exit 2
fi
source "$CONFIG_PATH"

require_configured() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == *CHANGEME* ]]; then
        echo "[ERROR] Configure $name before running this workflow." >&2
        exit 2
    fi
}

require_arguments_configured() {
    local name="$1"
    shift
    local argument
    for argument in "$@"; do
        if [[ "$argument" == *CHANGEME* ]]; then
            echo "[ERROR] Replace the placeholder in $name: $argument" >&2
            exit 2
        fi
    done
}

log_command() {
    printf '[INFO] Command:'
    printf ' %q' "$@"
    printf '\n'
}

if [[ "$ENABLE_TRAINING" != "0" && "$ENABLE_TRAINING" != "1" ]]; then
    echo "[ERROR] ENABLE_TRAINING must be 0 or 1; received: $ENABLE_TRAINING" >&2
    exit 2
fi
if [[ "$ENABLE_TRAINING" == "0" ]]; then
    echo "[INFO] Model training is disabled by: $CONFIG_PATH"
    exit 0
fi

require_configured "MODEL_ENV" "$MODEL_ENV"
require_arguments_configured "TRAIN_ARGS" "${TRAIN_ARGS[@]}"

if [[ ! -f "$MODEL_ENV/bin/activate" ]]; then
    echo "[ERROR] Model environment does not exist: $MODEL_ENV" >&2
    exit 2
fi

source "$MODEL_ENV/bin/activate"
if ! command -v yolo >/dev/null 2>&1; then
    echo "[ERROR] The configured environment does not provide the yolo command." >&2
    exit 2
fi

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Configuration: $CONFIG_PATH"
echo "[INFO] Model environment: $MODEL_ENV"
echo "[INFO] YOLO executable: $(command -v yolo)"
echo "[INFO] YOLO version: $(yolo version)"

TRAIN_COMMAND=(yolo "${TRAIN_ARGS[@]}")
echo "[INFO] Starting YOLO training."
log_command "${TRAIN_COMMAND[@]}"
"${TRAIN_COMMAND[@]}"

echo "[DONE] YOLO training completed."
