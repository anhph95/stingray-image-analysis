#!/usr/bin/env bash
###############################################################################
# Build the media/frame timestamp CSV needed by abundance on a local machine or
# local HPC node.
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

require_value() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == *CHANGEME* || "$value" == *DATE_CRUISE* || "$value" == *SENSOR_DATASET* ]]; then
        echo "[ERROR] Configure $name before running this workflow." >&2
        exit 2
    fi
}

require_dir() {
    local name="$1"
    local value="$2"
    require_value "$name" "$value"
    if [[ ! -d "$value" ]]; then
        echo "[ERROR] $name does not exist: $value" >&2
        exit 2
    fi
}

require_file() {
    local name="$1"
    local value="$2"
    require_value "$name" "$value"
    if [[ ! -f "$value" ]]; then
        echo "[ERROR] Expected output was not created: $name=$value" >&2
        exit 1
    fi
}

require_switch() {
    local name="$1"
    local value="$2"
    if [[ "$value" != "0" && "$value" != "1" ]]; then
        echo "[ERROR] $name must be 0 or 1; received: $value" >&2
        exit 2
    fi
}

require_switch "ENABLE_TIMESTAMPS" "$ENABLE_TIMESTAMPS"
if [[ "$ENABLE_TIMESTAMPS" == "0" ]]; then
    echo "[INFO] Frame timestamps are disabled by: $CONFIG_PATH"
    exit 0
fi
if [[ "$TIMESTAMP_MODE" != "fast" && "$TIMESTAMP_MODE" != "details" ]]; then
    echo "[ERROR] TIMESTAMP_MODE must be 'fast' or 'details'." >&2
    exit 2
fi

echo "[INFO] Run inputs:"
echo "  CONFIG_PATH=$CONFIG_PATH"
echo "  STINGRAY_DATA_ROOT=$STINGRAY_DATA_ROOT"
echo "  CRUISE=$CRUISE"
echo "  VIDEO_INPUT_DIR=$VIDEO_INPUT_DIR"
echo "  MEDIA_LIST_DIR=$MEDIA_LIST_DIR"
echo "  TIMESTAMP_MODE=$TIMESTAMP_MODE"
echo "  TIMESTAMP_FILE_LIMIT=$TIMESTAMP_FILE_LIMIT"
echo "  TIMESTAMP_SUFFIXES=${TIMESTAMP_SUFFIXES[*]}"

require_dir "STINGRAY_DATA_ROOT" "$STINGRAY_DATA_ROOT"
require_dir "VIDEO_INPUT_DIR" "$VIDEO_INPUT_DIR"
require_value "MEDIA_LIST_DIR" "$MEDIA_LIST_DIR"
require_value "CRUISE" "$CRUISE"

JOB_TMP="${TMPDIR:-/tmp}"
MAX_WORKERS="${TIMESTAMP_MAX_WORKERS:-$(nproc)}"

echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $CVISION_ENV"

source "$CVISION_ENV/bin/activate"

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

FRAME_ARGS=(
    --work-dir "$STINGRAY_DATA_ROOT"
    --cruise "$CRUISE"
    --media-dir "$VIDEO_INPUT_DIR"
    --out-dir "$MEDIA_LIST_DIR"
    --max-workers "$MAX_WORKERS"
    --suffix "${TIMESTAMP_SUFFIXES[@]}"
    --no-file-log
)

if [[ -n "$TIMESTAMP_FILE_LIMIT" ]]; then
    FRAME_ARGS+=(--file-limit "$TIMESTAMP_FILE_LIMIT")
fi

if [[ "$TIMESTAMP_MODE" == "details" ]]; then
    FRAME_ARGS+=(--details)
fi

stingray images frame-timestamp "${FRAME_ARGS[@]}"

require_file "VIDEO_LIST_CSV" "$VIDEO_LIST_CSV"
require_file "FRAME_LIST_CSV" "$FRAME_LIST_CSV"
echo "[DONE] Video list: $VIDEO_LIST_CSV"
echo "[DONE] Frame list: $FRAME_LIST_CSV"
