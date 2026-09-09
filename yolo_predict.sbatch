#!/usr/bin/env bash
#SBATCH --job-name=yolo_predict
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
#SBATCH --mail-type=ALL

###############################################################################
# Run resumable Ultralytics YOLO prediction with one worker per allocated GPU.
###############################################################################

set -euxo pipefail

# Record the allocation context before starting the portable workhorse.
echo "Job ID: $SLURM_JOB_ID, JobName: $SLURM_JOB_NAME"
hostname
pwd
date

# Load the cluster environment required by the configured virtual environment.
module purge
module load miniconda/25.9

# Let the workhorse divide videos across every GPU exposed by this allocation.
export STINGRAY_RUN_DEVICES="allocated"
export STINGRAY_RUN_ID="$SLURM_JOB_ID"

# Preserve the submission working directory for config, input, and output paths.
exec bash yolo_predict.sh "$@"
