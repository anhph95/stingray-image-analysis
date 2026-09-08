#!/usr/bin/env bash
###############################################################################
# Run Ultralytics YOLO prediction locally or from a Prefect shell task.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

###############################################################################
# Run configuration
###############################################################################

MODEL_ENV="$SCRIPT_DIR/.venv/cvision"

# Use the video-list CSV written by `stingray images frame-timestamp`.
CRUISE="CHANGEME_CRUISE_ID"
VIDEO_LIST_CSV="CHANGEME_VIDEO_LIST_CSV"
VIDEO_INPUT_DIR="CHANGEME_INPUT_PATH"
PREDICTION_WORK_DIR="CHANGEME_OUTPUT_PATH/yolo_work"
BUILD_VIDEO_LIST="0"

# Use BATCH_ID=all for one direct run or a non-negative integer for one batch.
BATCH_ID="${BATCH_ID:-all}"
BATCH_SIZE=100
PREDICTION_VIDEO_STATUSES=("valid")
PREDICTION_PROJECT="/proj/vast/omics/sosik/yolozone/inference_hrs2601"
PREDICTION_NAME="predict"

# Every entry is passed unchanged after `yolo`. Source, project, and name are
# appended at runtime from the video inventory and selected batch.
PREDICTION_ARGS=(
    mode=predict
    task=detect
    model=/proj/vast/omics/sosik/trained_yolo_models/train7/weights/best.pt
    save=False
    save_txt=True
    save_conf=True
    agnostic_nms=True
    iou=0.5
    conf=0.1
    half=False
    imgsz=1280
    batch=64
    device=0
    max_det=300
    vid_stride=1
    stream_buffer=False
    visualize=False
    augment=False
    retina_masks=False
    verbose=True
    show=False
    save_crop=False
    save_frames=False
    show_labels=True
    show_conf=True
    show_boxes=True
    exist_ok=True
)

###############################################################################
# End configuration
###############################################################################

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

log_command() {
    printf '[INFO] Command:'
    printf ' %q' "$@"
    printf '\n'
}

require_switch "BUILD_VIDEO_LIST" "$BUILD_VIDEO_LIST"
require_configured "MODEL_ENV" "$MODEL_ENV"
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

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Model environment: $MODEL_ENV"
echo "[INFO] YOLO executable: $(command -v yolo)"
echo "[INFO] YOLO version: $(yolo version)"

mkdir -p "$PREDICTION_WORK_DIR" "$PREDICTION_PROJECT"

if [[ "$BUILD_VIDEO_LIST" == "1" ]]; then
    require_configured "CRUISE" "$CRUISE"
    require_configured "VIDEO_INPUT_DIR" "$VIDEO_INPUT_DIR"
    if [[ ! -d "$VIDEO_INPUT_DIR" ]]; then
        echo "[ERROR] VIDEO_INPUT_DIR does not exist: $VIDEO_INPUT_DIR" >&2
        exit 2
    fi
    if ! command -v stingray >/dev/null 2>&1; then
        echo "[ERROR] BUILD_VIDEO_LIST=1 requires StingrayTools in MODEL_ENV." >&2
        exit 2
    fi
    VIDEO_LIST_OUT_DIR=$(dirname "$VIDEO_LIST_CSV")
    mkdir -p "$VIDEO_LIST_OUT_DIR"
    echo "[INFO] Building the video inventory with StingrayTools."
    stingray images frame-timestamp \
        --work-dir "$PREDICTION_WORK_DIR" \
        --cruise "$CRUISE" \
        --media-dir "$VIDEO_INPUT_DIR" \
        --out-dir "$VIDEO_LIST_OUT_DIR" \
        --max-workers "${MAX_WORKERS:-$(nproc)}" \
        --suffix .avi \
        --no-file-log
fi

if [[ ! -f "$VIDEO_LIST_CSV" ]]; then
    echo "[ERROR] VIDEO_LIST_CSV does not exist: $VIDEO_LIST_CSV" >&2
    exit 2
fi
echo "[INFO] Using timestamp video list: $VIDEO_LIST_CSV"

if [[ "$BATCH_ID" != "all" && ! "$BATCH_ID" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] BATCH_ID must be a non-negative integer or 'all'." >&2
    exit 2
fi
if [[ ! "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] BATCH_SIZE must be a positive integer." >&2
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
        --batch-size "$BATCH_SIZE" \
        --statuses "$STATUS_FILTER" \
        --output "$BATCH_SOURCE_LIST"
)

echo "[INFO] Eligible AVI files: $ELIGIBLE_COUNT"
echo "[INFO] BATCH_ID=$BATCH_ID BATCH_SIZE=$BATCH_SIZE selected=$SELECTED_COUNT"
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
log_command "${PREDICTION_COMMAND[@]}"
"${PREDICTION_COMMAND[@]}"
mkdir -p "$RUN_DIR"
touch "$SUCCESS_MARKER"
echo "[INFO] Batch completion marker: $SUCCESS_MARKER"
echo "[DONE] YOLO prediction completed."
