#!/usr/bin/env bash
# Settings shared by the Ollama and vLLM setups. Sourced by config/ollama.sh
# and config/vllm.sh -- you normally never source this directly.

# --- Where everything lives -------------------------------------------------
# Fastdata (/mnt/parscratch) has no quota, is fast (Lustre), and is reachable
# from BOTH the login nodes and the worker/GPU nodes. Your home directory
# (/users/$USER) is only 50 GB, so model weights and container images must
# NOT go there.
export PARSCRATCH="/mnt/parscratch/users/$USER"

# Keep Apptainer's build/pull cache off home too.
export APPTAINER_CACHEDIR="$PARSCRATCH/apptainer/cache"

# Refuse to run outside a SLURM job. Apptainer is only installed on Stanage's
# worker nodes, not the login nodes, and login nodes are shared and not meant
# for sustained compute anyway. SLURM_JOB_ID is set by both srun and sbatch
# and unset on a bare login-node shell, so its absence is a reliable "not in
# a job" signal. $1 is the command the caller should suggest instead.
# Override with STANAGE_ALLOW_NO_SLURM=1 for local/off-Stanage testing.
# Called by 00_setup.sh and start_ollama.sh.
_check_running_in_slurm_job() {
  local hint="$1"
  if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    return 0
  fi
  if [[ "${STANAGE_ALLOW_NO_SLURM:-0}" == "1" ]]; then
    echo "WARNING: no SLURM_JOB_ID detected, but continuing because" >&2
    echo "         STANAGE_ALLOW_NO_SLURM=1." >&2
    return 0
  fi
  echo "ERROR: no active SLURM job detected (SLURM_JOB_ID is unset)." >&2
  echo "       You appear to be on a login node ($(hostname)), where" >&2
  echo "       Apptainer is not installed. Start a job with (from the repo root):" >&2
  echo "         $hint" >&2
  echo "       Set STANAGE_ALLOW_NO_SLURM=1 to override (e.g. local testing)." >&2
  return 1
}
