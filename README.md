# Stingray Image Analysis

This repository provides independent jobs for frame timestamps, YOLO
inference, image abundance, and YOLO training. Cruise-processing jobs share one
config so their input and output paths remain consistent.

## Setup and Environment

Run the setup inside WSL2 and create the repository environment with the
default WSL2 Python:

```bash
git clone https://github.com/anhph95/stingray-image-analysis.git
cd stingray-image-analysis
python3 -m venv .venv/cvision
source .venv/cvision/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade pyyaml "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
```

The lightweight installation supports timestamps, detection-label merging,
and abundance. Install Ultralytics only when YOLO inference or training is
needed:

```bash
source .venv/cvision/bin/activate
python -m pip install --upgrade ultralytics
```

The `.venv` directory is ignored by Git. Slurm runners use the same configured
environment after `module purge` and `module load miniconda/25.9`.

## Configuration

Copy `configs/cruise.example.conf.sh` to `configs/my_cruise.conf.sh`, then edit
the cruise values, directory roots, environment, model, and abundance settings.
Frame timestamps, inference, and abundance all read this same config.

The timestamp job creates both shared artifacts: `VIDEO_LIST_CSV` for inference
and `FRAME_LIST_CSV` for abundance. Inference and abundance consume these files
without rebuilding them. Set a job's `ENABLE_*` value to `0` to make that job
exit without processing.

Training is independent of a cruise. Copy
`configs/yolo_train.example.conf.sh` to `configs/my_training.conf.sh` and edit
its environment and `TRAIN_ARGS`.

Run every command below from the repository root. The runners do not change
directories, so relative config, environment, and helper paths resolve from the
submission directory.

## Bash or Prefect

Run any required job directly in WSL2 or from a Prefect shell task:

```bash
bash frame_timestamps.sh configs/my_cruise.conf.sh
bash yolo_predict.sh configs/my_cruise.conf.sh
bash image_abundance.sh configs/my_cruise.conf.sh
bash yolo_train.sh configs/my_training.conf.sh
```

For inference, the default `BATCH_ID=all` processes all eligible videos. Set a
zero-based batch explicitly when needed, for example by prefixing the inference
command with `BATCH_ID=0`.

## Slurm

Create `slogs` before submission because Slurm opens log files before the job
script starts. Replace `YOUR_EMAIL` in each submitted command; every `.sbatch`
file already sets `#SBATCH --mail-type=ALL`.

```bash
mkdir -p slogs
sbatch --mail-user=YOUR_EMAIL frame_timestamps.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL --array=0-99%3 yolo_predict.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL image_abundance.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL yolo_train.sbatch configs/my_training.conf.sh
```

For inference, the number of array elements is
`ceil(eligible videos / PREDICTION_BATCH_SIZE)`. Therefore the last zero-based
array index is that value minus one. In `--array=0-99%3`, `0-99` selects 100
batches and `%3` limits execution to three concurrent array tasks.

Each job can be submitted independently when its required inputs already
exist. When jobs are submitted together, use Slurm `afterok` dependencies or an
external orchestrator so inference waits for timestamps and abundance waits for
the complete inference array.

## Job Reference

### Frame Timestamps

Scans `VIDEO_INPUT_DIR` and writes `VIDEO_LIST_CSV` and `FRAME_LIST_CSV`.
Configure `TIMESTAMP_MODE`, file limits, worker count, and video suffixes in the
timestamp section. Use `fast` normally and `details` when every frame must be
inspected.

### YOLO Inference

Reads eligible videos from `VIDEO_LIST_CSV` and writes batch directories under
`PREDICTION_PROJECT`. Configure model weights, batch size, accepted video
statuses, and native Ultralytics arguments in `PREDICTION_ARGS`. Successful
batches receive an `_SUCCESS` marker and are skipped when rerun.

### Image Abundance

Reads `FRAME_LIST_CSV`, prediction labels, class names, and `SENSOR_CSV`, then
writes `ABUNDANCE_OUT_CSV`. It never scans videos or regenerates timestamps.
When `MERGE_LABELS="1"`, it first builds `DETECTIONS_CSV` and `CLASS_MAP_CSV`
from the prediction label directories.

The abundance calculation filters detections by `SCORE_THRESH`, groups them
into time bins of width `BIN_WIDTH`, and converts counts to concentration using
`VOLUME_PER_FRAME`.

### YOLO Training

Uses the separate training config and passes `TRAIN_ARGS` unchanged to the
Ultralytics CLI. The configured device list must agree with the GPU resources
requested in `yolo_train.sbatch`.
