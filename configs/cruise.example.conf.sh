###############################################################################
# Global workflow identity and stage selection
###############################################################################

CRUISE="CHANGEME_CRUISE"
# Match the date parsed from the cruise media filenames (YYYYMMDD).
CRUISE_DATE="CHANGEME_YYYYMMDD"
CRUISE_COLLECTION="NESLTER"
CAMERA_STREAM="CHANGEME_CAMERA_STREAM"
VIDEO_SUFFIX=".avi"
RUN_NAME="${CRUISE_DATE}_${CRUISE}"

ENABLE_TIMESTAMPS="1"
ENABLE_PREDICTION="1"
ENABLE_ABUNDANCE="1"
TIMESTAMP_MODE="fast"

###############################################################################
# Environments, directory roots, and derived paths
###############################################################################

CVISION_ENV="$SCRIPT_DIR/.venv/cvision"
MODEL_ENV="$CVISION_ENV"

VIDEO_DATA_ROOT="CHANGEME_VIDEO_DATA_ROOT"
STINGRAY_DATA_ROOT="CHANGEME_STINGRAY_DATA_ROOT"
MODEL_OUTPUT_ROOT="CHANGEME_MODEL_OUTPUT_ROOT"

VIDEO_INPUT_DIR="${VIDEO_DATA_ROOT}/${CRUISE_COLLECTION}_${CRUISE}/${CAMERA_STREAM}"
MEDIA_LIST_DIR="${STINGRAY_DATA_ROOT}/media_list/${CAMERA_STREAM}"
ANALYSIS_WORK_DIR="${STINGRAY_DATA_ROOT}/image_abundance_work/${CAMERA_STREAM}"
PREDICTION_PROJECT="${MODEL_OUTPUT_ROOT}/inference_${CRUISE,,}"
PREDICTION_WORK_DIR="${PREDICTION_PROJECT}/work"

VIDEO_LIST_CSV="${MEDIA_LIST_DIR}/${RUN_NAME}_video_list_${TIMESTAMP_MODE}.csv"
FRAME_LIST_CSV="${MEDIA_LIST_DIR}/${RUN_NAME}_frame_list_${TIMESTAMP_MODE}.csv"
DETECTIONS_CSV="${ANALYSIS_WORK_DIR}/${RUN_NAME}_detection_labels.csv"
CLASS_MAP_CSV="${ANALYSIS_WORK_DIR}/${RUN_NAME}_class_map.csv"

SENSOR_DATASET="CHANGEME_SENSOR_DATASET"
ABUNDANCE_DATASET="shadowgraph"
SENSOR_CSV="${STINGRAY_DATA_ROOT}/dashboard_data/data/${SENSOR_DATASET}/${RUN_NAME}.csv"
ABUNDANCE_OUT_CSV="${STINGRAY_DATA_ROOT}/dashboard_data/data/${ABUNDANCE_DATASET}/${RUN_NAME}.csv"

###############################################################################
# Frame timestamp configuration
###############################################################################

TIMESTAMP_FILE_LIMIT=""
TIMESTAMP_MAX_WORKERS=""
TIMESTAMP_SUFFIXES=("$VIDEO_SUFFIX")

###############################################################################
# Model prediction configuration
###############################################################################

MODEL_WEIGHTS_PATH="CHANGEME_MODEL_WEIGHTS_PATH"
PREDICTION_NAME="predict"
PREDICTION_BATCH_SIZE=1000
PREDICTION_VIDEO_STATUSES=("valid")

PREDICTION_ARGS=(
    mode=predict
    task=detect
    "model=$MODEL_WEIGHTS_PATH"
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
# Image abundance configuration
###############################################################################

CLASS_YAML="CHANGEME_CLASS_NAMES_YAML"
MERGE_LABELS="1"
LABEL_DIRS=("$PREDICTION_PROJECT")

SCORE_THRESH="0.7"
BIN_WIDTH="5"
VOLUME_PER_FRAME="0.00225"
ADD_CI="0"
