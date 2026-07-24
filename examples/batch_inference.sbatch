#!/usr/bin/env bash
#
# Non-interactive batch inference over a dataset of prompts.
#
# This is the "scale past interactive" path: submit it and walk away. It grabs
# a GPU, starts the model, runs every prompt in examples/prompts.jsonl through
# it, writes the answers to fastdata, and shuts the server down.
#
# Submit from the repo root ON A LOGIN NODE (after running scripts/00_setup.sh):
#
#     sbatch examples/batch_inference.sbatch
#
# Watch it with:   squeue --me
# Cancel it with:  scancel <job-id>
#
# --- SLURM resource request -------------------------------------------------
#SBATCH --job-name=llm-batch
#SBATCH --partition=gpu             # A100 nodes; use gpu-h100 for H100 nodes
#SBATCH --qos=gpu                   # required for the GPU partitions on Stanage
#SBATCH --gres=gpu:1                # one GPU
#SBATCH --cpus-per-task=8
#SBATCH --mem=82G                   # ~ one A100's worth of host RAM
#SBATCH --time=01:00:00             # batch jobs may run up to 96:00:00
#SBATCH --output=llm-batch.%j.out   # %j = job id

set -euo pipefail

# SLURM starts the job in the directory you submitted from (the repo root).
source config/env.sh

echo "Job $SLURM_JOB_ID running $MODEL on $(hostname)"
apptainer exec --nv "$OLLAMA_SIF" nvidia-smi -L || true

# Start the server (this defines the `stop_ollama` helper too).
source scripts/start_ollama.sh

# Run inference. Results go to fastdata, keyed by job id so runs don't clobber.
OUT="$OLLAMA_DIR/results.$SLURM_JOB_ID.jsonl"
python examples/batch_infer.py examples/prompts.jsonl "$OUT"

# Always stop the server so the node is left clean.
stop_ollama

echo "Results written to $OUT"
