###############################################################################
# YOLO training configuration
###############################################################################

MODEL_ENV=".venv/cvision"

TRAIN_ARGS=(
    mode=train
    model=yolov8x
    data=CHANGEME_TRAINING_DATA_YAML
    epochs=200
    imgsz=1280
    batch=16
    device=0,1
    agnostic_nms=true
)
