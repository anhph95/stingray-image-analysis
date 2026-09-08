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
source "$SCRIPT_DIR/.venv/cvision/bin/activate"
echo "Environment loaded"
set -x

###############################################################################
# Job configuration
#
# Edit this block for each run.
###############################################################################

CRUISE="CHANGEME_CRUISE_ID"

# Some hosts mount this shared storage tree under /srv/vast instead of /proj.
WORK_DIR="/proj/nes-lter/Stingray/data"
CLASS_YAML="CHANGEME_CLASS_NAMES_YAML"
SENSOR_CSV="/proj/nes-lter/Stingray/data/dashboard_data/data/SENSOR_DATASET/DATE_CRUISE.csv"
MEDIA_CSV="/proj/nes-lter/Stingray/data/media_list/CAMERA_STREAM/DATE_CRUISE_frame_list_fast.csv"
DETECTIONS_CSV="/proj/nes-lter/Stingray/data/image_abundance_work/DATE_CRUISE_detection_labels.csv"
CLASS_MAP_CSV="/proj/nes-lter/Stingray/data/image_abundance_work/DATE_CRUISE_class_map.csv"
ABUNDANCE_OUT_CSV="/proj/nes-lter/Stingray/data/dashboard_data/data/shadowgraph/DATE_CRUISE.csv"

MERGE_LABELS="1"     # 1 = merge LABEL_DIRS into DETECTIONS_CSV; 0 = use existing DETECTIONS_CSV
BUILD_MEDIA_CSV="0"  # 1 = build media CSV before abundance; 0 = use existing MEDIA_CSV
MEDIA_DIR="CHANGEME_MEDIA_DIR"
MEDIA_OUT_DIR="/proj/nes-lter/Stingray/data/media_list/CAMERA_STREAM"
DETAILS="0"          # 1 = full per-frame timestamp extraction; 0 = fast frame count
FILE_LIMIT=""
SUFFIXES=(".avi" ".mp4" ".png" ".tiff")

SCORE_THRESH="0.7"
BIN_WIDTH="5"
VOLUME_PER_FRAME="0.00225"
ADD_CI="0"           # 1 = add Poisson confidence intervals; 0 = abundance only

LABEL_DIRS=(
    # "/path/to/ml-run/worker0/labels"
    # "/path/to/ml-run/worker1/labels"
    # "/path/to/ml-run/worker2/labels"
)

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

echo "[INFO] Run inputs:"
echo "  CRUISE=$CRUISE"
echo "  WORK_DIR=$WORK_DIR"
echo "  CLASS_YAML=$CLASS_YAML"
echo "  SENSOR_CSV=$SENSOR_CSV"
echo "  MEDIA_CSV=$MEDIA_CSV"
echo "  DETECTIONS_CSV=$DETECTIONS_CSV"
echo "  CLASS_MAP_CSV=$CLASS_MAP_CSV"
echo "  ABUNDANCE_OUT_CSV=$ABUNDANCE_OUT_CSV"
echo "  MERGE_LABELS=$MERGE_LABELS"
echo "  BUILD_MEDIA_CSV=$BUILD_MEDIA_CSV"
echo "  MEDIA_DIR=$MEDIA_DIR"
echo "  MEDIA_OUT_DIR=$MEDIA_OUT_DIR"
echo "  DETAILS=$DETAILS"
echo "  FILE_LIMIT=$FILE_LIMIT"
echo "  SUFFIXES=${SUFFIXES[*]}"
echo "  SCORE_THRESH=$SCORE_THRESH"
echo "  BIN_WIDTH=$BIN_WIDTH"
echo "  VOLUME_PER_FRAME=$VOLUME_PER_FRAME"
echo "  ADD_CI=$ADD_CI"
echo "  LABEL_DIRS=${LABEL_DIRS[*]}"

require_dir "WORK_DIR" "$WORK_DIR"
require_file "CLASS_YAML" "$CLASS_YAML"
require_file "SENSOR_CSV" "$SENSOR_CSV"
require_value "MEDIA_CSV" "$MEDIA_CSV"
require_value "DETECTIONS_CSV" "$DETECTIONS_CSV"
require_value "CLASS_MAP_CSV" "$CLASS_MAP_CSV"
require_value "ABUNDANCE_OUT_CSV" "$ABUNDANCE_OUT_CSV"

if [[ "$BUILD_MEDIA_CSV" == "1" ]]; then
    require_dir "MEDIA_DIR" "$MEDIA_DIR"
    require_value "MEDIA_OUT_DIR" "$MEDIA_OUT_DIR"
    require_value "CRUISE" "$CRUISE"
else
    require_file "MEDIA_CSV" "$MEDIA_CSV"
fi

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
echo "[INFO] Virtual environment: $SCRIPT_DIR/.venv/cvision"

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

mkdir -p "$(dirname "$DETECTIONS_CSV")" "$(dirname "$CLASS_MAP_CSV")" "$(dirname "$ABUNDANCE_OUT_CSV")"

if [[ "$BUILD_MEDIA_CSV" == "1" ]]; then
    mkdir -p "$MEDIA_OUT_DIR"
    echo "[INFO] Building media CSV."
    FRAME_ARGS=(
        --work-dir "$WORK_DIR"
        --cruise "$CRUISE"
        --media-dir "$MEDIA_DIR"
        --out-dir "$MEDIA_OUT_DIR"
        --max-workers "$JOBS"
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
fi

require_file "MEDIA_CSV" "$MEDIA_CSV"

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
    --media-csv "$MEDIA_CSV"
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
