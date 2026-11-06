#!/usr/bin/env bash
#
# ONE-TIME SETUP for the Snakemake + vLLM batch workflow. Run it ONCE, as a
# CPU job, from the repo root on a Stanage login node:
#
#   sbatch --mem=16G --cpus-per-task=4 --time=03:00:00 \
#          --wrap="bash workflows/vllm-batch/scripts/setup.sh"
#
# It does two things, both into fastdata ($PARSCRATCH/vllm):
#   1. Pulls the pinned vLLM container image (~10 GB; this is the slow part).
#   2. Creates a Python virtual environment (module Python + venv, as the
#      Stanage Python docs recommend) with Snakemake and its SLURM executor
#      plugin -- the "controller" side of the workflow.
#
# Model weights are NOT downloaded here: the workflow's download_model step
# fetches whichever model config.yaml names, so changing models needs no
# re-setup. Safe to re-run; finished steps are skipped.
#
# The Python module is VLLM_PYTHON_MODULE in config/env.sh (override it with
# an env var if the default stops resolving).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$WF/../.." && pwd)"
# shellcheck source=config/env.sh
source "$ROOT/config/env.sh"

SETUP_CMD='sbatch --mem=16G --cpus-per-task=4 --time=03:00:00 --wrap="bash workflows/vllm-batch/scripts/setup.sh"'
_check_running_in_slurm_job "$SETUP_CMD" || exit 1

if ! command -v apptainer >/dev/null 2>&1; then
  echo "ERROR: 'apptainer' not found on $(hostname). It is only installed on" >&2
  echo "       Stanage worker nodes. From a login node, run:" >&2
  echo "         $SETUP_CMD" >&2
  exit 1
fi
if [[ ! -d /mnt/parscratch ]]; then
  echo "ERROR: /mnt/parscratch not found. This script must run on Stanage." >&2
  exit 1
fi

# Prompts, completions and logs will live under $VLLM_DIR, on a cluster-wide
# filesystem: create every level we own as mode 700 (one level at a time,
# because `mkdir -p -m` only applies the mode to the last component). Existing
# directories are left alone, as in scripts/00_setup.sh.
umask 077
for _dir in "$PARSCRATCH" "$VLLM_DIR" "$VLLM_DIR/cache" "$VLLM_DIR/runs" \
            "$VLLM_DIR/tmp" "$HF_HOME" \
            "$PARSCRATCH/apptainer" "$APPTAINER_CACHEDIR"; do
  if [[ ! -d "$_dir" ]]; then
    mkdir -m 700 "$_dir" 2>/dev/null || [[ -d "$_dir" ]] || {
      echo "ERROR: could not create $_dir" >&2
      exit 1
    }
  fi
done
unset _dir

_mode="$(stat -c %a "$VLLM_DIR")"
if (( 8#$_mode & 8#77 )) && [[ "${STANAGE_ALLOW_OPEN_FASTDATA:-0}" != "1" ]]; then
  echo "WARNING: $VLLM_DIR is mode $_mode -- other users can read your" >&2
  echo "         prompts and results. Fix with: chmod -R go-rwx '$VLLM_DIR'" >&2
fi

# --- 1. Container image ------------------------------------------------------
if [[ -f "$VLLM_SIF" ]]; then
  echo "==> Image already present: $VLLM_SIF (skipping pull)"
else
  if [[ ! -w "$(dirname "$VLLM_SIF")" ]]; then
    echo "ERROR: $VLLM_SIF does not exist and $(dirname "$VLLM_SIF") is not" >&2
    echo "       writable. If VLLM_SIF points at a shared copy, ask its owner" >&2
    echo "       to pull it, or unset VLLM_SIF to use your own fastdata." >&2
    exit 1
  fi
  echo "==> Pulling $VLLM_IMAGE (~10 GB, can take 30+ minutes) ..."
  # A killed earlier pull leaves a .partial behind, which apptainer refuses
  # to overwrite.
  rm -f "$VLLM_SIF.partial"
  # Unpacking the layers needs >10 GB of temp space, so by default it goes on
  # fastdata rather than /tmp or the home quota. Node-local scratch is faster
  # for these many small files if the node has room: VLLM_PULL_TMPDIR=$TMPDIR.
  # --disable-cache: the image is pinned by digest, so a layer cache in
  # APPTAINER_CACHEDIR would never be reused -- just ~10 GB of duplicate small
  # files on fastdata.
  APPTAINER_TMPDIR="${VLLM_PULL_TMPDIR:-$VLLM_DIR/tmp}" \
    apptainer pull --disable-cache "$VLLM_SIF.partial" "$VLLM_IMAGE"
  mv "$VLLM_SIF.partial" "$VLLM_SIF"
  echo "==> Image saved to $VLLM_SIF"
fi
echo "==> vLLM version in image:"
# Stanage binds $HOME into containers; ignore any `pip install --user`
# packages in ~/.local so they cannot shadow the image's own vLLM.
PYTHONNOUSERSITE=1 apptainer exec "$VLLM_SIF" python3 -c "import vllm; print('    ', vllm.__version__)" ||
  echo "    (import check failed without a GPU -- re-check inside a GPU job)" >&2
echo

# --- 2. Controller environment ----------------------------------------------
_load_vllm_python_module
if [[ -x "$VLLM_ENV/bin/snakemake" ]]; then
  echo "==> Environment already present: $VLLM_ENV (re-syncing packages)"
else
  echo "==> Creating Python virtual environment at $VLLM_ENV ($(python --version)) ..."
  # No --system-site-packages: keep the controller isolated from packages
  # bundled with the Python module.
  python -m venv "$VLLM_ENV"
fi
# pip cache on fastdata too, so the env doesn't fill the home quota.
PIP_CACHE_DIR="$VLLM_DIR/cache/pip" \
  "$VLLM_ENV/bin/python" -m pip install --quiet -r "$WF/requirements.txt"
echo "==> Snakemake $("$VLLM_ENV/bin/snakemake" --version) ready in $VLLM_ENV"

echo
echo "Setup complete. Next, from the repo root on a login node:"
echo "  sbatch workflows/vllm-batch/run_workflow.sbatch"
echo "or with your own data/model:"
echo "  sbatch workflows/vllm-batch/run_workflow.sbatch --config input=my_prompts.jsonl run_name=exp1"
