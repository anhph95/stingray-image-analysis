# Stingray Image Analysis

This repository provides independent Bash and Slurm jobs for video timestamp
generation, model inference, image abundance, and model training. Cruise jobs
share one configuration so that every job resolves the same inputs and output
artifacts without repeating path settings.

## Environment Setup

Run the local setup inside WSL2. Using WSL2 gives the virtual environment the
Linux layout expected by the Bash runners and by the cluster environment.

Clone the repository and create the `cvision` environment with the default
WSL2 Python:

```bash
git clone https://github.com/anhph95/stingray-image-analysis.git
cd stingray-image-analysis
python3 -m venv .venv/cvision
source .venv/cvision/bin/activate
python --version
python -m pip install --upgrade pip setuptools wheel
```

Install the lightweight image-processing dependencies. These are sufficient
for timestamp generation, detection-label merging, and abundance:

```bash
python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
```

Install Ultralytics separately when this environment will run YOLO inference
or training:

```bash
python -m pip install --upgrade ultralytics
```

The `.venv` directory is ignored by Git and must not be committed. The generic
name `cvision` allows the environment to support model frameworks other than
YOLO when their runners are added.

Every Slurm runner loads `miniconda/25.9` and then activates the configured
virtual environment. The fixed module version prevents a different cluster
Python from being selected for an existing environment. If the cluster module
changes, update all `.sbatch` runners together and rebuild the environment with
the new Python version.

## Cruise Configuration

Create one configuration for a cruise:

```bash
cp configs/cruise.example.conf.sh configs/my_cruise.conf.sh
```

Edit every `CHANGEME_*` value in the copied file. The shared section defines the
cruise identity, environment, directory roots, and derived artifact paths.
`CRUISE_DATE` must use `YYYYMMDD` and match the date parsed from the video
filenames.

The shared artifacts are derived consistently:

```text
VIDEO_INPUT_DIR      VIDEO_DATA_ROOT/CRUISE_COLLECTION_CRUISE/CAMERA_STREAM
VIDEO_LIST_CSV       MEDIA_LIST_DIR/RUN_NAME_video_list_MODE.csv
FRAME_LIST_CSV       MEDIA_LIST_DIR/RUN_NAME_frame_list_MODE.csv
PREDICTION_PROJECT   MODEL_OUTPUT_ROOT/inference_cruise
DETECTIONS_CSV       ANALYSIS_WORK_DIR/RUN_NAME_detection_labels.csv
CLASS_MAP_CSV        ANALYSIS_WORK_DIR/RUN_NAME_class_map.csv
ABUNDANCE_OUT_CSV    .../ABUNDANCE_DATASET/RUN_NAME.csv
```

The same config then contains one section for each cruise job. Set its
`ENABLE_*` switch to `0` when that job should exit without processing. Passing
the same config to different jobs does not make them run each other's steps.

Run every Bash and Slurm command below from the repository root. The runners do
not change directories; relative config, environment, and helper paths resolve
from the directory where `bash` or `sbatch` is invoked.

Before submitting any Slurm job, create the log directory from the repository
root. Slurm opens its output files before the job script starts:

```bash
mkdir -p slogs
```

## Available Jobs

### Frame Timestamps

This job scans `VIDEO_INPUT_DIR` once and creates both shared artifacts:

- `VIDEO_LIST_CSV` contains the video inventory used by inference.
- `FRAME_LIST_CSV` contains frame times used by abundance.

Configure `ENABLE_TIMESTAMPS`, `TIMESTAMP_MODE`, `TIMESTAMP_FILE_LIMIT`,
`TIMESTAMP_MAX_WORKERS`, and `TIMESTAMP_SUFFIXES`. Use `TIMESTAMP_MODE="fast"`
for the fast StingrayTools implementation or `"details"` when detailed
per-frame inspection is required.

Run directly in WSL2 or from a Prefect shell task:

```bash
bash frame_timestamps.sh configs/my_cruise.conf.sh
```

Submit the same job to Slurm:

```bash
sbatch frame_timestamps.sbatch configs/my_cruise.conf.sh
```

Capture the Slurm job ID when a later inference submission should wait for the
two lists:

```bash
TIMESTAMP_JOB=$(sbatch --parsable frame_timestamps.sbatch configs/my_cruise.conf.sh)
```

### YOLO Inference

This job reads `VIDEO_LIST_CSV`, selects eligible videos, and writes prediction
batches below `PREDICTION_PROJECT`. It does not scan videos or create frame
timestamps.

Configure `ENABLE_PREDICTION`, `MODEL_WEIGHTS_PATH`, `PREDICTION_BATCH_SIZE`,
`PREDICTION_VIDEO_STATUSES`, and `PREDICTION_ARGS`. Keep `save_txt=True` and
`save_conf=True` when the predictions will be used by the abundance job.

Run all eligible videos directly:

```bash
bash yolo_predict.sh configs/my_cruise.conf.sh
```

Run only one zero-based batch directly by setting `BATCH_ID`:

```bash
BATCH_ID=0 bash yolo_predict.sh configs/my_cruise.conf.sh
```

For Slurm, the required number of array elements is:

```text
number of batches = ceil(eligible videos / PREDICTION_BATCH_SIZE)
last array index  = number of batches - 1
```

For example, `--array=0-99%3` runs 100 batches and allows at most three array
elements to use GPUs concurrently:

```bash
sbatch --array=0-99%3 yolo_predict.sbatch configs/my_cruise.conf.sh
```

If timestamp generation was just submitted, make inference wait for it and
capture the prediction-array job ID:

```bash
PREDICTION_JOB=$(sbatch --parsable --dependency="afterok:$TIMESTAMP_JOB" --array=0-99%3 yolo_predict.sbatch configs/my_cruise.conf.sh)
```

A successful batch writes an independent output directory and `_SUCCESS`
marker. Rerunning the same batch skips it when that marker already exists.

### Image Abundance

This job reads the existing `FRAME_LIST_CSV`, prediction labels, class names,
and `SENSOR_CSV`, then writes `ABUNDANCE_OUT_CSV`. It does not scan videos,
create a video list, or regenerate frame timestamps.

Configure `ENABLE_ABUNDANCE`, `CLASS_YAML`, `MERGE_LABELS`, `LABEL_DIRS`,
`SCORE_THRESH`, `BIN_WIDTH`, `VOLUME_PER_FRAME`, and `ADD_CI`.

When `MERGE_LABELS="1"`, the job consolidates the prediction `.txt` files into
`DETECTIONS_CSV` and creates `CLASS_MAP_CSV`. When `MERGE_LABELS="0"`, it uses
the existing detection table and creates only a missing class map from
`CLASS_YAML`.

Run directly in WSL2 or from a Prefect shell task:

```bash
bash image_abundance.sh configs/my_cruise.conf.sh
```

Submit directly to Slurm when its required inputs already exist:

```bash
sbatch image_abundance.sbatch configs/my_cruise.conf.sh
```

If inference was submitted as an array, make abundance wait until every array
element succeeds:

```bash
sbatch --dependency="afterok:$PREDICTION_JOB" image_abundance.sbatch configs/my_cruise.conf.sh
```

The abundance calculation aligns detections to frame times, bins them with
width `BIN_WIDTH`, filters detections below `SCORE_THRESH`, and converts counts
to concentration using `VOLUME_PER_FRAME`.

### YOLO Training

Training is independent of cruise processing and uses its own configuration.
Create that config and edit its model, dataset, device, and training arguments:

```bash
cp configs/yolo_train.example.conf.sh configs/my_training.conf.sh
```

Run training directly in WSL2 or from a Prefect shell task:

```bash
bash yolo_train.sh configs/my_training.conf.sh
```

Submit training to Slurm. The configured `device` list must agree with the GPU
resources requested in `yolo_train.sbatch`:

```bash
sbatch yolo_train.sbatch configs/my_training.conf.sh
```

Arguments in `TRAIN_ARGS` are passed unchanged to the native Ultralytics CLI;
omitted settings retain their Ultralytics defaults.

## Slurm Status and Logs

Inspect queued and running jobs:

```bash
squeue -u "$USER"
```

Read standard output and error under `slogs/`. Timestamp, inference, abundance,
and training use distinct Slurm job names, and inference log names also include
the array-task ID.
