#!/usr/bin/env bash
#SBATCH --job-name=yolo_predict
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
#SBATCH --mail-type=ALL

###############################################################################
# Run resumable Ultralytics YOLO prediction with one worker per allocated GPU.
###############################################################################

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

require_file() {
    local name="$1"
    local value="$2"
    require_configured "$name" "$value"
    if [[ ! -f "$value" ]]; then
        echo "[ERROR] $name does not exist: $value" >&2
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

require_configured "MODEL_ENV" "$MODEL_ENV"
require_configured "PREDICTION_PROJECT" "$PREDICTION_PROJECT"
require_configured "VIDEO_SUFFIX" "$VIDEO_SUFFIX"
require_file "MODEL_WEIGHTS_PATH" "$MODEL_WEIGHTS_PATH"
require_file "VIDEO_LIST_CSV" "$VIDEO_LIST_CSV"
require_arguments_configured "PREDICTION_ARGS" "${PREDICTION_ARGS[@]}"

FILE_LIMIT="${PREDICTION_FILE_LIMIT:-}"
if [[ -n "$FILE_LIMIT" && ! "$FILE_LIMIT" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] PREDICTION_FILE_LIMIT must be empty or a positive integer." >&2
    exit 2
fi
if [[ ! -f "$MODEL_ENV/bin/activate" ]]; then
    echo "[ERROR] Model environment does not exist: $MODEL_ENV" >&2
    exit 2
fi

source "$MODEL_ENV/bin/activate"
if ! command -v python >/dev/null 2>&1; then
    echo "[ERROR] The configured environment does not provide Python." >&2
    exit 2
fi

mkdir -p "$PREDICTION_PROJECT"
STATUS_FILTER=$(IFS=,; echo "${PREDICTION_VIDEO_STATUSES[*]}")

echo "[INFO] Configuration: $CONFIG_PATH"
echo "[INFO] Environment: $MODEL_ENV"
echo "[INFO] CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-unset}"

PREDICT_COMMAND=(
    python yolo_predict.py
    --video-list "$VIDEO_LIST_CSV"
    --statuses "$STATUS_FILTER"
    --suffix "$VIDEO_SUFFIX"
    --model "$MODEL_WEIGHTS_PATH"
    --project "$PREDICTION_PROJECT"
    --devices allocated
    --run-id "$SLURM_JOB_ID"
)
if [[ -n "$FILE_LIMIT" ]]; then
    PREDICT_COMMAND+=(--file-limit "$FILE_LIMIT")
fi
PREDICT_COMMAND+=("${PREDICTION_ARGS[@]}")

"${PREDICT_COMMAND[@]}"
