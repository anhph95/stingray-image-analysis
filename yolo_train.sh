#!/usr/bin/env bash
###############################################################################
# Run Ultralytics YOLO training locally or from a Prefect shell task.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

###############################################################################
# Run configuration
###############################################################################

MODEL_ENV="$SCRIPT_DIR/.venv/cvision"

# Every entry is passed unchanged after `yolo`.
TRAIN_ARGS=(
    mode=train
    model=yolov8x
    data=/proj/omics/sosik/yolozone/training_data/data.yaml
    epochs=200
    imgsz=1280
    batch=16
    device=0,1
    agnostic_nms=true
)

###############################################################################
# End configuration
###############################################################################

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
echo "[INFO] Model environment: $MODEL_ENV"
echo "[INFO] YOLO executable: $(command -v yolo)"
echo "[INFO] YOLO version: $(yolo version)"

TRAIN_COMMAND=(yolo "${TRAIN_ARGS[@]}")
echo "[INFO] Starting YOLO training."
log_command "${TRAIN_COMMAND[@]}"
"${TRAIN_COMMAND[@]}"

echo "[DONE] YOLO training completed."
