#!/usr/bin/env bash
###############################################################################
# Build the media/frame timestamp CSV needed by abundance on a local machine or
# local HPC node.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

###############################################################################
# Run configuration
###############################################################################

WORK_DIR="/mnt/vast/nes-lter/Stingray/data"
CRUISE="CHANGEME_CRUISE_ID"
MEDIA_DIR="CHANGEME_MEDIA_DIR"
OUT_DIR="/mnt/vast/nes-lter/Stingray/data/media_list/CAMERA_STREAM"
DETAILS="0"  # 1 = full per-frame timestamp extraction; 0 = fast frame count

# Optional filters. Leave FILE_LIMIT empty for full production runs.
FILE_LIMIT=""
SUFFIXES=(".avi" ".mp4" ".png" ".tiff")

###############################################################################
# End configuration
###############################################################################

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

echo "[INFO] Run inputs:"
echo "  WORK_DIR=$WORK_DIR"
echo "  CRUISE=$CRUISE"
echo "  MEDIA_DIR=$MEDIA_DIR"
echo "  OUT_DIR=$OUT_DIR"
echo "  DETAILS=$DETAILS"
echo "  FILE_LIMIT=$FILE_LIMIT"
echo "  SUFFIXES=${SUFFIXES[*]}"

require_dir "WORK_DIR" "$WORK_DIR"
require_dir "MEDIA_DIR" "$MEDIA_DIR"
require_value "OUT_DIR" "$OUT_DIR"
require_value "CRUISE" "$CRUISE"

JOB_TMP="${TMPDIR:-/tmp}"
MAX_WORKERS="${MAX_WORKERS:-$(nproc)}"

echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $SCRIPT_DIR/.venv/cvision"

source "$SCRIPT_DIR/.venv/cvision/bin/activate"

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

FRAME_ARGS=(
    --work-dir "$WORK_DIR"
    --cruise "$CRUISE"
    --media-dir "$MEDIA_DIR"
    --out-dir "$OUT_DIR"
    --max-workers "$MAX_WORKERS"
    --suffix "${SUFFIXES[@]}"
    --no-file-log
)

if [[ -n "$FILE_LIMIT" ]]; then
    FRAME_ARGS+=(--file-limit "$FILE_LIMIT")
fi

if [[ "$DETAILS" == "1" ]]; then
    FRAME_ARGS+=(--details)
fi

stingray images frame-timestamp "${FRAME_ARGS[@]}"

echo "[DONE] Frame timestamp CSV written under: $OUT_DIR"
