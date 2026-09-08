#!/usr/bin/env bash
#SBATCH --job-name=image_abundance
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=compute
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
##SBATCH --mail-type=ALL
##SBATCH --mail-user=your.email@example.edu

###############################################################################
# Run post-inference image abundance processing in one Slurm job.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Job ID: $SLURM_JOB_ID, JobName: $SLURM_JOB_NAME"
hostname
pwd
date
module purge
module load miniconda/25.9
set -x

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

require_file() {
    local name="$1"
    local value="$2"
    require_value "$name" "$value"
    if [[ ! -f "$value" ]]; then
        echo "[ERROR] $name does not exist: $value" >&2
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

require_switch() {
    local name="$1"
    local value="$2"
    if [[ "$value" != "0" && "$value" != "1" ]]; then
        echo "[ERROR] $name must be 0 or 1; received: $value" >&2
        exit 2
    fi
}

echo "[INFO] Run inputs:"
echo "  CONFIG_PATH=$CONFIG_PATH"
echo "  CRUISE=$CRUISE"
echo "  STINGRAY_DATA_ROOT=$STINGRAY_DATA_ROOT"
echo "  CLASS_YAML=$CLASS_YAML"
echo "  SENSOR_CSV=$SENSOR_CSV"
echo "  FRAME_LIST_CSV=$FRAME_LIST_CSV"
echo "  DETECTIONS_CSV=$DETECTIONS_CSV"
echo "  CLASS_MAP_CSV=$CLASS_MAP_CSV"
echo "  ABUNDANCE_OUT_CSV=$ABUNDANCE_OUT_CSV"
echo "  MERGE_LABELS=$MERGE_LABELS"
echo "  SCORE_THRESH=$SCORE_THRESH"
echo "  BIN_WIDTH=$BIN_WIDTH"
echo "  VOLUME_PER_FRAME=$VOLUME_PER_FRAME"
echo "  ADD_CI=$ADD_CI"
echo "  LABEL_DIRS=${LABEL_DIRS[*]}"

require_switch "ENABLE_ABUNDANCE" "$ENABLE_ABUNDANCE"
require_switch "MERGE_LABELS" "$MERGE_LABELS"
require_switch "ADD_CI" "$ADD_CI"
if [[ "$ENABLE_ABUNDANCE" == "0" ]]; then
    echo "[INFO] Image abundance is disabled by: $CONFIG_PATH"
    exit 0
fi

require_dir "STINGRAY_DATA_ROOT" "$STINGRAY_DATA_ROOT"
require_file "CLASS_YAML" "$CLASS_YAML"
require_file "SENSOR_CSV" "$SENSOR_CSV"
require_file "FRAME_LIST_CSV" "$FRAME_LIST_CSV"
require_value "DETECTIONS_CSV" "$DETECTIONS_CSV"
require_value "CLASS_MAP_CSV" "$CLASS_MAP_CSV"
require_value "ABUNDANCE_OUT_CSV" "$ABUNDANCE_OUT_CSV"

if [[ "$MERGE_LABELS" == "1" ]]; then
    if [[ ${#LABEL_DIRS[@]} -eq 0 ]]; then
        echo "[ERROR] Add at least one label directory to LABEL_DIRS." >&2
        exit 2
    fi

    for label_dir in "${LABEL_DIRS[@]}"; do
        require_dir "LABEL_DIR" "$label_dir"
    done
else
    require_file "DETECTIONS_CSV" "$DETECTIONS_CSV"
fi

JOB_TMP="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}"
JOBS="${SLURM_CPUS_PER_TASK:-$(nproc)}"

mkdir -p slogs

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $CVISION_ENV"

source "$CVISION_ENV/bin/activate"
echo "Environment loaded"

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

mkdir -p "$(dirname "$DETECTIONS_CSV")" "$(dirname "$CLASS_MAP_CSV")" "$(dirname "$ABUNDANCE_OUT_CSV")"

if [[ "$MERGE_LABELS" == "1" ]]; then
    echo "[INFO] Merging detection labels."
    bash "$SCRIPT_DIR/merge_detection_labels.sh" \
        --output-csv "$DETECTIONS_CSV" \
        --class-map-csv "$CLASS_MAP_CSV" \
        --class-yaml "$CLASS_YAML" \
        --python-bin "$(command -v python)" \
        --jobs "$JOBS" \
        "${LABEL_DIRS[@]}"
elif [[ ! -f "$CLASS_MAP_CSV" ]]; then
    echo "[INFO] Class map CSV not found; creating it from CLASS_YAML."
    python "$SCRIPT_DIR/build_class_map.py" \
        --class-yaml "$CLASS_YAML" \
        --class-map-csv "$CLASS_MAP_CSV"
else
    echo "[INFO] Reusing existing class map CSV: $CLASS_MAP_CSV"
fi

echo "[INFO] Computing abundance."
ABUNDANCE_ARGS=(
    --detections-csv "$DETECTIONS_CSV"
    --class-map-csv "$CLASS_MAP_CSV"
    --sensor-csv "$SENSOR_CSV"
    --media-csv "$FRAME_LIST_CSV"
    --out-csv "$ABUNDANCE_OUT_CSV"
    --score-thresh "$SCORE_THRESH"
    --bin-width "$BIN_WIDTH"
    --volume-per-frame "$VOLUME_PER_FRAME"
)

if [[ "$ADD_CI" == "1" ]]; then
    ABUNDANCE_ARGS+=(--add-ci)
fi

stingray images abundance "${ABUNDANCE_ARGS[@]}" --no-file-log

echo "[DONE] Image abundance output: $ABUNDANCE_OUT_CSV"
