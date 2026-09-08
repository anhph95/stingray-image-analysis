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

Clone the workflow repository, then create the shared computer-vision
environment used for development and by the workflow runners:

```bash
git clone https://github.com/anhph95/stingray-image-analysis.git
cd stingray-image-analysis

module load miniconda/25.9
python -m venv .venv/cvision
source .venv/cvision/bin/activate
python --version
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
python -m pip install --upgrade ultralytics # only for training or inference run
```

Run these commands inside WSL2 so the environment has the Linux layout expected
by the Bash and Slurm runners. The `.venv` directory is ignored by Git and must
not be committed.

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
- `run_local.sh` builds optional media CSV, merges labels, and computes
  abundance on a local machine or HPC node.
- `run_slurm.sbatch` builds optional media CSV, merges labels, and computes
  abundance as one Slurm job.
- `run_frame_timestamps_local.sh` builds only the media/frame timestamp CSV.
- `run_frame_timestamps_slurm.sbatch` builds only the media/frame timestamp CSV
  as one Slurm job.
- `run_yolo.sh` runs native Ultralytics training and/or inference from one
  editable configuration block. It can be called directly or by a scheduler.
- `run_yolo_slurm.sbatch` supplies Slurm resources and calls `run_yolo.sh`.

## Environment

The workflow uses `.venv/cvision` for media timestamps, label merging,
abundance, and model execution. The `stingraytools[images]` dependency set
includes OpenCV and the scientific dependencies used by image processing;
Ultralytics supplies the initial YOLO training and inference commands. Future
model runners can use the same environment when their dependencies are
compatible.

## YOLO Training and Inference

Copy `run_yolo.sh` for a specific analysis run and edit its configuration block.
Use `RUN_TRAINING` and `RUN_INFERENCE` to run either step independently or to
run both in sequence. All entries in `TRAIN_ARGS` and `INFERENCE_ARGS` are
passed unchanged after `yolo`. Settings omitted from those arrays remain native
Ultralytics defaults and are not added to the command log.

The included training values reproduce the working command:

```bash
yolo mode=train \
  model=yolov8x \
  data=/srv/omics/sosik/yolozone/training_data/data.yaml \
  epochs=200 \
  imgsz=1280 \
  batch=16 \
  device=0,1 \
  agnostic_nms=true
```

Before inference, the script uses the `_video_list_` CSV written by `stingray
images frame-timestamp`. The fast timestamp mode is the normal choice; detailed
mode remains available when every frame must be inspected. The included
inference values reflect the updated run parameters. Each parallel batch uses
`batch=64` and logical `device=0`; Slurm assigns one physical GPU to each array
task.

Set `BUILD_VIDEO_LIST=1` when the runner should invoke the fast StingrayTools
timestamp command before inference. Set `VIDEO_LIST_CSV` to the exact output
file expected from the configured cruise and media filenames. Leave the switch
disabled to reuse a previously generated inventory.

Keep `save_txt=True` and `save_conf=True` when the results will feed
`merge_detection_labels.sh`. Ultralytics then produces the six-column detection
rows expected by the existing label merger.

Run the configured workflow directly with:

```bash
bash run_yolo.sh
```

A direct run defaults to `BATCH_ID=all`. A scheduler can set a numeric
`BATCH_ID` to select `BATCH_SIZE` eligible rows from the same immutable video
list. Successful batches receive independent output directories and completion
markers.

The log includes the configured computer-vision environment, installed YOLO
version, enabled steps, number of selected videos, and each complete command.
It does not enumerate settings that Ultralytics supplies by default.

## YOLO with Slurm

For inference arrays, set `RUN_TRAINING=0` in `run_yolo.sh`. Each array element
requests one GPU, while the percentage suffix limits total concurrent GPUs.
For example, 100 batches using at most three GPUs are submitted with
`--array=0-99%3`.

The Slurm adapter loads `miniconda/25.9` when the Environment Modules command is
available. Set `MINICONDA_MODULE` to another module name when needed. Direct and
Prefect execution call `run_yolo.sh` without loading an HPC module.

Create the log directory before submitting because Slurm opens output files
before the job script begins:

```bash
mkdir -p slogs
sbatch --array=0-99%3 run_yolo_slurm.sbatch
```

Run training separately with `RUN_INFERENCE=0`, one array element, and enough
GPUs for the explicit training device list. For the included `device=0,1`
setting:

```bash
sbatch --array=0-0 --gres=gpu:2 run_yolo_slurm.sbatch
```

## YOLO with Prefect

No Prefect-specific flow is included. A Prefect shell task can invoke the same
configured workflow used locally and by Slurm:

```bash
bash /path/to/stingray-image-analysis/run_yolo.sh
```

Prefect captures the script's standard output and error, including the YOLO
version and explicit command arguments. The Prefect worker must have access to
the configured environment, media, model, and output paths.

## Data Paths

Edit paths directly in the runner configuration block. Shared storage may be
mounted under `/mnt/vast` or `/srv/vast`.

```bash
CLASS_YAML="/path/to/class_names.yaml"
SENSOR_CSV="/path/to/stingray/data/dashboard_data/data/SENSOR_DATASET/DATE_CRUISE.csv"
MEDIA_CSV="/path/to/stingray/data/media_list/CAMERA_STREAM/DATE_CRUISE_frame_list_fast.csv"
DETECTIONS_CSV="/path/to/stingray/data/image_abundance_work/DATE_CRUISE_detection_labels.csv"
CLASS_MAP_CSV="/path/to/stingray/data/image_abundance_work/DATE_CRUISE_class_map.csv"
ABUNDANCE_OUT_CSV="/path/to/stingray/data/dashboard_data/data/shadowgraph/DATE_CRUISE.csv"
```

The file naming template is:

```text
DATE_CRUISE.csv
DATE_CRUISE_video_list_fast.csv
DATE_CRUISE_frame_list_fast.csv
DATE_CRUISE_detection_labels.csv
DATE_CRUISE_class_map.csv
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

## Local Run

Edit the configuration block in `run_local.sh`, then run:

```bash
bash run_local.sh
```

For media CSV generation only:

```bash
bash run_frame_timestamps_local.sh
```

## Slurm Run

Edit the configuration block and `#SBATCH` resources in `run_slurm.sbatch`,
then submit:

```bash
sbatch run_slurm.sbatch
```

For media CSV generation only:

```bash
sbatch run_frame_timestamps_slurm.sbatch
```

## Command Steps

The workflow runners call these processing steps:

```bash
stingray images frame-timestamp ...
bash merge_detection_labels.sh ...
stingray images abundance ...
```
