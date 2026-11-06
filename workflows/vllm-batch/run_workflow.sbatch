#!/usr/bin/env bash
#
# Run the Snakemake + vLLM batch workflow. This job is the lightweight
# CONTROLLER: it runs Snakemake on a CPU node, which downloads the model,
# splits your prompts into shards and submits one GPU job per shard, then
# merges the results. It holds no GPU itself.
#
# Submit from the repo root ON A LOGIN NODE (after workflows/vllm-batch/scripts/setup.sh):
#
#   sbatch workflows/vllm-batch/run_workflow.sbatch
#   sbatch workflows/vllm-batch/run_workflow.sbatch --config input=my_prompts.jsonl run_name=exp1
#   sbatch workflows/vllm-batch/run_workflow.sbatch -n          # dry run: show the plan only
#
# Any arguments are passed straight to `snakemake`.
#
# Watch it:   squeue --me      (this job + one llm job per running shard)
# Results:    /mnt/parscratch/users/$USER/vllm/runs/<run_name>/results.jsonl
#
#SBATCH --job-name=llm-workflow
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
# Long enough to wait for GPU jobs to queue AND run. If it runs out, just
# resubmit: finished shards are kept and only the rest are redone.
#SBATCH --time=24:00:00
#SBATCH --output=/mnt/parscratch/users/%u/vllm/llm-workflow.%j.out
##SBATCH --mail-user=you@sheffield.ac.uk
##SBATCH --mail-type=END,FAIL

set -euo pipefail

# Prompts and completions are written under $VLLM_DIR; keep them private.
umask 077

if [[ ! -f config/env.sh ]]; then
  echo "ERROR: submit this from the repo root (config/env.sh not found in $PWD)." >&2
  exit 1
fi
# shellcheck source=config/env.sh
source config/env.sh

if [[ ! -x "$VLLM_ENV/bin/snakemake" || ! -f "$VLLM_SIF" ]]; then
  echo "ERROR: one-time setup not done. From a login node, in the repo root, run:" >&2
  echo '  sbatch --mem=16G --cpus-per-task=4 --time=03:00:00 --wrap="bash workflows/vllm-batch/scripts/setup.sh"' >&2
  exit 1
fi
# Load the Python module the venv was built from, then use the venv
# (the pattern in the Stanage Python docs' batch example).
_load_vllm_python_module
export PATH="$VLLM_ENV/bin:$PATH"

echo "Controller job $SLURM_JOB_ID on $(hostname); Snakemake $(snakemake --version)"
# The SLURM plugin prints a warning (and pauses 5 s) because it is itself
# running inside a job. That is expected here.
snakemake \
  --snakefile workflows/vllm-batch/Snakefile \
  --workflow-profile workflows/vllm-batch/profiles/stanage \
  --slurm-logdir "$VLLM_DIR/slurm-logs" \
  "$@"
