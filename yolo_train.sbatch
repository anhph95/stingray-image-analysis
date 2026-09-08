#!/usr/bin/env bash
#SBATCH --job-name=yolo_train
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err

###############################################################################
# Run Ultralytics YOLO training as one Slurm job.
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

echo "[INFO] Configuration: $CONFIG_PATH"
echo "[INFO] Environment: $MODEL_ENV"

TRAIN_COMMAND=(yolo "${TRAIN_ARGS[@]}")
echo "[INFO] Starting YOLO training."
"${TRAIN_COMMAND[@]}"

echo "[DONE] YOLO training completed."
