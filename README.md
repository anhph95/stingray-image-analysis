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
without rebuilding them. Run only the jobs required for the current workflow.

Abundance intermediate files are written below
`workspace/abundance/CAMERA_STREAM/` in the repository and are ignored by Git.
The completed `ABUNDANCE_OUT_CSV` remains in the configured Stingray data
output directory.

Training is independent of a cruise. Copy
`configs/yolo_train.example.conf.sh` to `configs/my_training.conf.sh` and edit
its environment and `TRAIN_ARGS`.

Run every command below from the repository root. The runners do not change
directories, so relative config, environment, and helper paths resolve from the
submission directory.

## Bash

Run any required job directly in WSL2:

```bash
bash frame_timestamps.sh configs/my_cruise.conf.sh
bash yolo_predict.sh configs/my_cruise.conf.sh
bash image_abundance.sh configs/my_cruise.conf.sh
bash yolo_train.sh configs/my_training.conf.sh
```

Inference uses `LOCAL_PREDICTION_DEVICES` from the cruise config and loads the
model once on each selected device. Set `PREDICTION_FILE_LIMIT=6` to process
only the first six remaining videos; leave it empty to process all remaining
videos.

## Prefect container jobs

The timestamp and abundance Prefect flows run the existing shell jobs from the
lightweight `ghcr.io/anhph95/stingray-image-analysis:latest` container. Deploy
them with the generic deployment helper in `amplify-prefect`:

```bash
python src/deploy_flow.py https://github.com/anhph95/stingray-image-analysis.git prefect_flows.py:frame_timestamps stingray-frame-timestamps
python src/deploy_flow.py https://github.com/anhph95/stingray-image-analysis.git prefect_flows.py:image_abundance stingray-image-abundance
```

For each run, provide the host `config_path` and every top-level path used by
that config in `data_roots`, such as `["/proj"]`. Abundance also requires a
persistent host `workspace_dir`; the flow mounts it as `/app/workspace` inside
the container.

The container pins StingrayTools to a release tag with `STINGRAYTOOLS_REF` in
`docker/stingray-image-analysis/Dockerfile`. When StingrayTools is released,
update that tag and rebuild the image. Existing images remain unchanged.

## Slurm

Create `slogs` before submission because Slurm opens log files before the job
script starts. Replace `YOUR_EMAIL` in each submitted command; every `.sbatch`
file already sets `#SBATCH --mail-type=ALL`.

```bash
mkdir -p slogs
sbatch --mail-user=YOUR_EMAIL frame_timestamps.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL --gres=gpu:3 yolo_predict.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL image_abundance.sbatch configs/my_cruise.conf.sh
sbatch --mail-user=YOUR_EMAIL yolo_train.sbatch configs/my_training.conf.sh
```

Inference is one multi-GPU job, not a Slurm array. The command above requests
three GPUs; omit `--gres=gpu:3` to use the script's one-GPU default. Each GPU
loads the model once and draws videos from the same remaining-work queue.

Each job can be submitted independently when its required inputs already
exist. When jobs are submitted together, use Slurm `afterok` dependencies or an
external orchestrator so inference waits for timestamps and abundance waits for
the complete inference job.

## Job Reference

### Frame Timestamps

Scans `VIDEO_INPUT_DIR` and writes `VIDEO_LIST_CSV` and `FRAME_LIST_CSV`.
Configure `TIMESTAMP_MODE`, file limits, worker count, and video suffixes in the
timestamp section. Use `fast` normally and `details` when every frame must be
inspected.

### YOLO Inference

Reads eligible videos from `VIDEO_LIST_CSV` and removes videos already marked
complete. Slurm outputs are organized as
`PREDICTION_PROJECT/runs/SLURM_JOB_ID/worker_ID/VIDEO_ID`. Every allocated GPU
loads the model once and processes videos from a shared queue. A video receives
an `_SUCCESS` marker only after inference completes, so later runs may use a
different GPU count and automatically process only the remaining videos.

### Image Abundance

Reads `FRAME_LIST_CSV`, prediction labels, class names, and `SENSOR_CSV`, then
writes `ABUNDANCE_OUT_CSV`. It never scans videos or regenerates timestamps.
When `MERGE_LABELS="1"`, it first builds `DETECTIONS_CSV` and `CLASS_MAP_CSV`
from outputs registered by per-video `_SUCCESS` markers or the existing
Prefect `.completed_files.txt` manifest. Partial outputs from failed videos are
ignored.

The abundance calculation filters detections by `SCORE_THRESH`, groups them
into time bins of width `BIN_WIDTH`, and converts counts to concentration using
`VOLUME_PER_FRAME`.

### YOLO Training

Uses the separate training config and passes `TRAIN_ARGS` unchanged to the
Ultralytics CLI. The configured device list must agree with the GPU resources
requested in `yolo_train.sbatch`.
