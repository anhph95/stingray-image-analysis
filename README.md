# Stingray Image Analysis Workflow

This workflow merges ML detection labels, builds optional media/frame timestamp
CSVs, and computes time-binned shadowgraph abundance from existing Stingray
sensor data. The included merge helper reads space-separated `.txt` label
files; other ML pipelines can provide the same detection and class-map tables
directly.

The repository also contains standalone YOLO training and inference runners
that can be invoked directly or by Slurm and Prefect. They invoke the native
Ultralytics CLI and do not replace its configuration, training, prediction,
checkpointing, validation, or resume behavior.

## Setup

Inside WSL2, clone the workflow repository and create the shared
computer-vision environment with the default WSL2 Python:

```bash
git clone https://github.com/anhph95/stingray-image-analysis.git
cd stingray-image-analysis

python3 -m venv .venv/cvision
source .venv/cvision/bin/activate
python --version
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
```

This lightweight installation supports timestamp generation, label merging,
and abundance processing. The environment has the Linux layout expected by the
Bash and Slurm runners. The `.venv` directory is ignored by Git and must not be
committed.

Install Ultralytics separately only when this environment will run YOLO
training or prediction:

```bash
source .venv/cvision/bin/activate
python -m pip install --upgrade ultralytics
```

Other model frameworks can be installed in the same environment only when
their runners require them.

Pull the repositories and refresh the package installation when workflow files,
StingrayTools, or model dependencies should be updated. The environment is
named `cvision` because the workflow can support multiple computer-vision model
families; Ultralytics YOLO is the first configured runner, not an environment
boundary.

## Files

- `merge_detection_labels.sh` scans label directories and writes one detection
  table plus one class-map table.
- `build_class_map.py` parses model class names and writes the canonical class
  map without embedding Python inside a shell runner.
- `select_video_batch.py` safely filters and slices timestamp video-list CSVs
  for direct or Slurm-array inference.
- `configs/cruise.example.conf.sh` defines one cruise and derives consistent
  timestamp, prediction, detection, and abundance paths.
- `configs/yolo_train.example.conf.sh` contains model-training settings that do
  not belong to a cruise-processing run.
- `image_abundance.sh` consumes the completed frame list and detection results,
  then merges labels and computes abundance directly.
- `image_abundance.sbatch` contains the same abundance pipeline for Slurm.
- `frame_timestamps.sh` scans the videos and builds the shared video and frame
  lists directly.
- `frame_timestamps.sbatch` builds the same two shared lists as one Slurm job.
- `yolo_train.sh` runs native Ultralytics training directly or from a
  Prefect shell task.
- `yolo_train.sbatch` contains the same training pipeline with Slurm
  resources and module setup.
- `yolo_predict.sh` runs native Ultralytics prediction directly or
  from a Prefect shell task.
- `yolo_predict.sbatch` contains the same prediction pipeline with a
  Slurm GPU array configuration.

## Environment

The workflow uses `.venv/cvision` for media timestamps, label merging,
abundance, and model execution. The `stingraytools[images]` dependency set
includes OpenCV and the scientific dependencies used by image processing;
Ultralytics supplies the initial YOLO training and inference commands. Future
model runners can use the same environment when their dependencies are
compatible.

## Cruise Configuration

Copy the cruise template once for each cruise and edit only the copied config:

```bash
cp configs/cruise.example.conf.sh configs/my_cruise.conf.sh
```

The first section contains the cruise values and artifact paths shared by all
three flows. `RUN_NAME` is always `CRUISE_DATE_CRUISE`; `CRUISE_DATE` must match
the date parsed from the media filenames. Directory roots are configured once,
then all operational paths are derived consistently:

```text
VIDEO_INPUT_DIR      VIDEO_DATA_ROOT/CRUISE_COLLECTION_CRUISE/CAMERA_STREAM
VIDEO_LIST_CSV       MEDIA_LIST_DIR/RUN_NAME_video_list_MODE.csv
FRAME_LIST_CSV       MEDIA_LIST_DIR/RUN_NAME_frame_list_MODE.csv
PREDICTION_PROJECT   MODEL_OUTPUT_ROOT/inference_cruise
DETECTIONS_CSV       ANALYSIS_WORK_DIR/RUN_NAME_detection_labels.csv
CLASS_MAP_CSV        ANALYSIS_WORK_DIR/RUN_NAME_class_map.csv
ABUNDANCE_OUT_CSV    .../ABUNDANCE_DATASET/RUN_NAME.csv
```

The remaining config sections correspond directly to timestamp, inference, and
abundance. Set that section's `ENABLE_*` value to `0` when a flow should be
skipped. Every direct and Slurm runner accepts this same cruise config as its
first argument.

The timestamp flow creates both shared list artifacts. Inference reads
`VIDEO_LIST_CSV`; abundance reads `FRAME_LIST_CSV`. These are handoffs between
flows: neither inference nor abundance scans videos or regenerates timestamps.

## Run the Three Flows

After editing the cruise config, run the enabled flows in order. The direct
runners work in WSL2 and can also be invoked by Prefect:

```bash
bash frame_timestamps.sh configs/my_cruise.conf.sh
bash yolo_predict.sh configs/my_cruise.conf.sh
bash image_abundance.sh configs/my_cruise.conf.sh
```

The first command writes `VIDEO_LIST_CSV` and `FRAME_LIST_CSV`. The second reads
the video list and writes model predictions. The third reads the frame list,
the predictions, and `SENSOR_CSV`, then writes `ABUNDANCE_OUT_CSV`.

For Slurm, create the log directory once and submit the same three flows with
dependencies. `afterok` prevents a downstream flow from starting unless its
upstream job completed successfully:

```bash
mkdir -p slogs
TIMESTAMP_JOB=$(sbatch --parsable frame_timestamps.sbatch configs/my_cruise.conf.sh)
PREDICTION_JOB=$(sbatch --parsable --dependency="afterok:$TIMESTAMP_JOB" --array=0-99%3 yolo_predict.sbatch configs/my_cruise.conf.sh)
sbatch --dependency="afterok:$PREDICTION_JOB" image_abundance.sbatch configs/my_cruise.conf.sh
```

Adjust `--array=0-99%3` to match the required number of prediction batches and
the allowed GPU concurrency. A dependency on the prediction array waits for all
array elements before abundance begins.

## YOLO Training

Copy `configs/yolo_train.example.conf.sh` for a training run and edit the copied
configuration. Both training runners consume that file; the Slurm runner adds
only scheduler resources, job logging, and module setup. Every entry in
`TRAIN_ARGS` is passed unchanged after `yolo`, and omitted settings remain
native Ultralytics defaults.

The included training values reproduce the working command:

```bash
yolo mode=train \
  model=yolov8x \
  data=/proj/omics/sosik/yolozone/training_data/data.yaml \
  epochs=200 \
  imgsz=1280 \
  batch=16 \
  device=0,1 \
  agnostic_nms=true
```

Run training directly or submit it to Slurm with enough GPUs for the explicit
device list:

```bash
bash yolo_train.sh configs/my_training.conf.sh
mkdir -p slogs
sbatch yolo_train.sbatch configs/my_training.conf.sh
```

## YOLO Prediction

Both prediction runners load the same cruise configuration. The Slurm runner
adds scheduler resources, job logging, module setup, and its array task ID.
Every entry in `PREDICTION_ARGS` is passed unchanged after `yolo`.

Before prediction, the runner uses the `_video_list_` CSV written by `stingray
images frame-timestamp`. Fast timestamp mode is the normal choice; detailed
mode remains available when every frame must be inspected. Each parallel batch
uses `batch=64` and logical `device=0`; Slurm assigns one physical GPU to each
array task.

Keep `save_txt=True` and `save_conf=True` when results will feed
`merge_detection_labels.sh`. Ultralytics then produces the six-column detection
rows expected by the existing label merger.

Run all eligible videos directly with:

```bash
bash yolo_predict.sh configs/my_cruise.conf.sh
```

A direct run defaults to `BATCH_ID=all`; set a numeric `BATCH_ID` to run one
`PREDICTION_BATCH_SIZE` slice. Successful batches receive independent output
directories and completion markers.

The log includes the configured computer-vision environment, installed YOLO
version, enabled steps, number of selected videos, and each complete command.
It does not enumerate settings that Ultralytics supplies by default.

For Slurm prediction, each array element requests one GPU while the percentage
suffix limits concurrent GPUs. For example, submit 100 batches using at most
three GPUs with `--array=0-99%3`.

Every Slurm runner explicitly purges loaded modules and loads
`miniconda/25.9` before activating `.venv/cvision`. Keeping the module version
fixed makes the jobs reproducible and prevents an automatically selected Python
version from becoming incompatible with the existing virtual environment. If
the cluster changes its supported Miniconda module, update the fixed module in
all Slurm runners and rebuild the environment with that Python version. Local
runners and the WSL2 setup do not load HPC modules and can be invoked by
Prefect.

Create `slogs` before submitting because Slurm opens output files before the job
script begins. The complete dependency-based submission sequence is shown in
`Run the Three Flows`.

## YOLO with Prefect

No Prefect-specific flow is included. Prefect shell tasks can invoke the local
training or prediction pipelines:

```bash
bash /path/to/stingray-image-analysis/yolo_train.sh configs/my_training.conf.sh
bash /path/to/stingray-image-analysis/yolo_predict.sh configs/my_cruise.conf.sh
```

Prefect captures the script's standard output and error, including the YOLO
version and explicit command arguments. The Prefect worker must have access to
the configured environment, media, model, and output paths.

## Output Names

The derived file naming template is:

```text
CRUISE_DATE_CRUISE.csv
CRUISE_DATE_CRUISE_video_list_MODE.csv
CRUISE_DATE_CRUISE_frame_list_MODE.csv
CRUISE_DATE_CRUISE_detection_labels.csv
CRUISE_DATE_CRUISE_class_map.csv
```

The canonical detection table contains one row per retained model detection:

```text
media,frame,class_id,confidence
```

The class map contains one row per model class:

```text
class_id,class,source_file,source_format
```

If `MERGE_LABELS="1"`, the runner builds both tables from `LABEL_DIRS` and
`CLASS_YAML`. If `MERGE_LABELS="0"`, the runner uses an existing detection table.
When `CLASS_MAP_CSV` is missing, the runner creates it from `CLASS_YAML` before
computing abundance.

## Command Steps

The workflow runners call these processing steps:

```bash
stingray images frame-timestamp ...
bash merge_detection_labels.sh ...
stingray images abundance ...
```
