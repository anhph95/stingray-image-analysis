#!/usr/bin/env bash
#SBATCH --job-name=frame_timestamps
#SBATCH --cpus-per-task=12
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=compute
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
##SBATCH --mail-type=ALL
##SBATCH --mail-user=your.email@example.edu

###############################################################################
# Build the media/frame timestamp CSV needed by abundance.
###############################################################################

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# LOGGING JOB DETAILS

echo "Job ID: $SLURM_JOB_ID, JobName: $SLURM_JOB_NAME"
hostname; pwd; date

# Environment Setup

module purge
module load miniconda/25.9

set -eux

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

require_dir "STINGRAY_DATA_ROOT" "$STINGRAY_DATA_ROOT"
require_dir "VIDEO_INPUT_DIR" "$VIDEO_INPUT_DIR"
require_value "MEDIA_LIST_DIR" "$MEDIA_LIST_DIR"
require_value "CRUISE" "$CRUISE"

MAX_WORKERS="${TIMESTAMP_MAX_WORKERS:-${SLURM_CPUS_PER_TASK:-$(nproc)}}"

echo "[INFO] Configuration: $CONFIG_PATH"
echo "[INFO] Environment: $CVISION_ENV"
source "$CVISION_ENV/bin/activate"
echo "Environment loaded"

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
