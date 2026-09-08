#!/usr/bin/env bash
###############################################################################
# Run Ultralytics YOLO prediction locally or from a Prefect shell task.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

CONFIG_PATH="${1:-}"
if [[ -z "$CONFIG_PATH" ]]; then
    echo "[ERROR] Provide a cruise configuration file." >&2
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

BATCH_ID="${BATCH_ID:-all}"

require_switch() {
    local name="$1"
    local value="$2"
    if [[ "$value" != "0" && "$value" != "1" ]]; then
        echo "[ERROR] $name must be 0 or 1; received: $value" >&2
        exit 2
    fi
}

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

require_switch "ENABLE_PREDICTION" "$ENABLE_PREDICTION"
if [[ "$ENABLE_PREDICTION" == "0" ]]; then
    echo "[INFO] Model prediction is disabled by: $CONFIG_PATH"
    exit 0
fi
require_configured "MODEL_ENV" "$MODEL_ENV"
require_configured "CRUISE" "$CRUISE"
require_configured "VIDEO_SUFFIX" "$VIDEO_SUFFIX"
require_configured "PREDICTION_WORK_DIR" "$PREDICTION_WORK_DIR"
require_configured "PREDICTION_PROJECT" "$PREDICTION_PROJECT"
require_configured "PREDICTION_NAME" "$PREDICTION_NAME"
require_configured "VIDEO_LIST_CSV" "$VIDEO_LIST_CSV"
require_arguments_configured "PREDICTION_ARGS" "${PREDICTION_ARGS[@]}"

if [[ ! -f "$MODEL_ENV/bin/activate" ]]; then
    echo "[ERROR] Model environment does not exist: $MODEL_ENV" >&2
    exit 2
fi

source "$MODEL_ENV/bin/activate"
if ! command -v yolo >/dev/null 2>&1; then
    echo "[ERROR] The configured environment does not provide the yolo command." >&2
    exit 2
fi
if ! command -v python >/dev/null 2>&1; then
    echo "[ERROR] The configured environment does not provide Python." >&2
    exit 2
fi

echo "[INFO] Configuration: $CONFIG_PATH"
echo "[INFO] Environment: $MODEL_ENV"

mkdir -p "$PREDICTION_WORK_DIR" "$PREDICTION_PROJECT"

if [[ ! -f "$VIDEO_LIST_CSV" ]]; then
    echo "[ERROR] VIDEO_LIST_CSV does not exist: $VIDEO_LIST_CSV" >&2
    exit 2
fi
echo "[INFO] Using timestamp video list: $VIDEO_LIST_CSV"

if [[ "$BATCH_ID" != "all" && ! "$BATCH_ID" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] BATCH_ID must be a non-negative integer or 'all'." >&2
    exit 2
fi
if [[ ! "$PREDICTION_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] PREDICTION_BATCH_SIZE must be a positive integer." >&2
    exit 2
fi

if [[ "$BATCH_ID" == "all" ]]; then
    BATCH_LABEL="all"
else
    printf -v BATCH_LABEL '%06d' "$BATCH_ID"
fi
BATCH_SOURCE_LIST="$PREDICTION_WORK_DIR/source_${BATCH_LABEL}.txt"
STATUS_FILTER=$(IFS=,; echo "${PREDICTION_VIDEO_STATUSES[*]}")

read -r ELIGIBLE_COUNT SELECTED_COUNT < <(
    python "$SCRIPT_DIR/select_video_batch.py" \
        --video-list "$VIDEO_LIST_CSV" \
        --batch-id "$BATCH_ID" \
        --batch-size "$PREDICTION_BATCH_SIZE" \
        --statuses "$STATUS_FILTER" \
        --suffix "$VIDEO_SUFFIX" \
        --output "$BATCH_SOURCE_LIST"
)

echo "[INFO] Eligible AVI files: $ELIGIBLE_COUNT"
echo "[INFO] BATCH_ID=$BATCH_ID PREDICTION_BATCH_SIZE=$PREDICTION_BATCH_SIZE selected=$SELECTED_COUNT"
if [[ "$SELECTED_COUNT" -eq 0 ]]; then
    echo "[INFO] No videos assigned to this batch; nothing to run."
    exit 0
fi

BATCH_NAME="${PREDICTION_NAME}_${BATCH_LABEL}"
RUN_DIR="$PREDICTION_PROJECT/$BATCH_NAME"
SUCCESS_MARKER="$RUN_DIR/_SUCCESS"
if [[ -f "$SUCCESS_MARKER" ]]; then
    echo "[INFO] Batch already complete: $SUCCESS_MARKER"
    exit 0
fi

PREDICTION_COMMAND=(
    yolo
    "${PREDICTION_ARGS[@]}"
    "source=$BATCH_SOURCE_LIST"
    "project=$PREDICTION_PROJECT"
    "name=$BATCH_NAME"
)
echo "[INFO] Starting YOLO prediction."
"${PREDICTION_COMMAND[@]}"
mkdir -p "$RUN_DIR"
touch "$SUCCESS_MARKER"
echo "[INFO] Batch completion marker: $SUCCESS_MARKER"
echo "[DONE] YOLO prediction completed."
