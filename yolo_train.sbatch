#!/usr/bin/env bash
#SBATCH --job-name=yolo_train
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
#SBATCH --mail-type=ALL

###############################################################################
# Run Ultralytics YOLO training as one Slurm job.
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

# Preserve the submission working directory for config, input, and output paths.
exec bash yolo_train.sh "$@"
