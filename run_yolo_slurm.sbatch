#!/usr/bin/env bash
#SBATCH --job-name=yolo_workflow
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --array=0-0%3
#SBATCH --output=slogs/%A_%a.%x.out
#SBATCH --error=slogs/%A_%a.%x.err

###############################################################################
# Submit the shared YOLO workflow through Slurm.
#
# For parallel inference, change the array's final index to number_of_batches-1.
# Each array task receives one GPU and run_yolo.sh selects its inventory batch.
# Use a one-element array and edit GPU resources for multi-GPU training.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Job ID: ${SLURM_JOB_ID:-not-set}, JobName: ${SLURM_JOB_NAME:-yolo_workflow}"
hostname
pwd
date

MINICONDA_MODULE="${MINICONDA_MODULE:-miniconda/25.9}"
if command -v module >/dev/null 2>&1; then
    module purge
    module load "$MINICONDA_MODULE"
else
    echo "[INFO] Environment Modules unavailable; using the existing shell environment."
fi

bash "$SCRIPT_DIR/run_yolo.sh"
