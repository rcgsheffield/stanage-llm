#!/usr/bin/env bash
#
# ONE-TIME SETUP -- run this ONCE, as a small CPU job launched from a Stanage
# login node (run from the repo root):
#
#   sbatch --mem=8G --cpus-per-task=2 --time=02:00:00 --wrap="bash scripts/00_setup.sh"
#
# (or `srun ...` instead of `sbatch ... --wrap=...` to watch it in the
# foreground; sbatch survives an SSH disconnect, so it is preferred.)
#
# It does two things, both into fastdata (/mnt/parscratch):
#   1. Pulls the Ollama container image from Docker Hub (~1 GB).
#   2. Pre-downloads your chosen model's weights.
#
# It must run inside a SLURM job because Apptainer is only installed on the
# worker nodes, not the login nodes:
# https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/apptainer.html
# Everything lands in fastdata, which the GPU nodes share, so your later GPU
# job runs completely offline -- it just reads the local files.
#
# No GPU and no root are needed for this step. --time=02:00:00 leaves room
# for the largest models in the README table (~40 GB of weights).

set -euo pipefail

# Resolve the repo root from this script's location, then load config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../config/env.sh
source "$ROOT/config/env.sh"

_check_ollama_host_loopback || exit 1

SETUP_SRUN="sbatch --mem=8G --cpus-per-task=2 --time=02:00:00 --wrap=\"bash scripts/00_setup.sh\""

# --- Sanity checks ----------------------------------------------------------
# Before printing anything else, so a login-node run fails with one clear
# message rather than after output that looks like setup has started.
_check_running_in_slurm_job "$SETUP_SRUN" || exit 1

if ! command -v apptainer >/dev/null 2>&1; then
  echo "ERROR: 'apptainer' not found on $(hostname)." >&2
  echo "       On Stanage it is installed on the worker nodes only (not the" >&2
  echo "       login nodes), and no 'module load' is needed. From a login" >&2
  echo "       node, in the repo root, run:" >&2
  echo "         $SETUP_SRUN" >&2
  exit 1
fi

if [[ ! -d /mnt/parscratch ]]; then
  echo "ERROR: /mnt/parscratch not found. This script must run on Stanage." >&2
  exit 1
fi

echo "==> Model to prepare : $MODEL"
echo "==> Fastdata area     : $OLLAMA_DIR"
echo

# --- Create the fastdata area, privately ------------------------------------
# Everything below is written to fastdata, a cluster-wide filesystem. The
# default umask (0022) would make those files world-readable, and we
# deliberately don't chmod a directory you already created (see the loop
# below), so in that case the file mode is the only protection left. Safe to
# set globally here: this script is executed, not sourced.
umask 077

# The Stanage docs create /mnt/parscratch/users/$USER as mode 700 ("your area
# will only be accessible to you") but nothing does it for you. Create each
# level we own as 700 -- note `mkdir -p -m 700 a/b/c` applies the mode only to
# the deepest component and leaves the parents at the umask default, so create
# one level at a time instead.
#
# Directories that ALREADY exist are left untouched: a 755 area may be the
# public/ + private/ layout the Stanage docs also describe, and silently
# tightening a directory you chose to share would break it.
# _check_fastdata_perms (below) warns about them instead.
for _dir in "$PARSCRATCH" "$OLLAMA_DIR" "$OLLAMA_MODELS" \
            "$PARSCRATCH/apptainer" "$APPTAINER_CACHEDIR"; do
  if [[ ! -d "$_dir" ]]; then
    # Tolerate a concurrent create (another job racing us) rather than dying.
    mkdir -m 700 "$_dir" 2>/dev/null || [[ -d "$_dir" ]] || {
      echo "ERROR: could not create $_dir" >&2
      exit 1
    }
  fi
done
unset _dir

# Opt-in remediation for an area created world-readable by an earlier version
# of this script (or by hand). Off by default: a setup script shouldn't
# chmod -R someone's multi-GB model tree unasked, and we can't tell a leftover
# 0022 default from a directory you deliberately shared. Scoped to what this
# repo creates -- the mode of $PARSCRATCH itself is your call, and $OLLAMA_DIR
# at 700 already blocks traversal to everything inside it. 'go-rwx' rather
# than 700 so directories keep their owner 'x' bit.
if [[ "${STANAGE_FIX_PERMS:-0}" == "1" ]]; then
  echo "==> STANAGE_FIX_PERMS=1: removing group/other access under $OLLAMA_DIR"
  chmod -R go-rwx "$OLLAMA_DIR" "$PARSCRATCH/apptainer"
fi

# Run last, so a clean first install prints nothing and STANAGE_FIX_PERMS=1
# silences its own warning within the same invocation.
_check_fastdata_perms

# --- 1. Pull the container image (skip if already present) ------------------
if [[ -f "$OLLAMA_SIF" ]]; then
  echo "==> Image already present: $OLLAMA_SIF (skipping pull)"
else
  echo "==> Pulling Ollama image from Docker Hub ($OLLAMA_IMAGE) ..."
  apptainer pull "$OLLAMA_SIF" "$OLLAMA_IMAGE"
  echo "==> Image saved to $OLLAMA_SIF"
fi
echo

# --- 2. Pre-download the model ---------------------------------------------
# Start a temporary server (CPU is fine for downloading -- no --nv), pull the
# model, then stop the server. We share the config with the other scripts.
# -B mounts fastdata into the container -- unlike home, it is not auto-mounted
# by Apptainer, so without this OLLAMA_MODELS would resolve to a path that
# doesn't exist inside the container and the download would silently land in
# the container's throwaway overlay instead of persisting on fastdata.
echo "==> Starting a temporary Ollama server to download '$MODEL' ..."
apptainer exec -B /mnt/parscratch \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama serve >"$OLLAMA_DIR/setup-server.log" 2>&1 &
SERVER_PID=$!

# Make sure we always stop the temporary server, even on error/Ctrl-C.
cleanup() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for the server to accept connections.
echo -n "==> Waiting for server to be ready"
for _ in $(seq 1 60); do
  if curl -fsS "http://$OLLAMA_HOST" >/dev/null 2>&1; then
    ready=1; break
  fi
  echo -n "."
  sleep 1
done
echo
if [[ "${ready:-0}" != "1" ]]; then
  echo "ERROR: Ollama server did not start. See $OLLAMA_DIR/setup-server.log" >&2
  exit 1
fi

echo "==> Downloading model weights for '$MODEL' (this can take a few minutes) ..."
apptainer exec -B /mnt/parscratch \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama pull "$MODEL"

echo
echo "==> Models now available in $OLLAMA_MODELS:"
apptainer exec -B /mnt/parscratch \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama list

echo
echo "==> Disk used by models: $(du -sh "$OLLAMA_MODELS" 2>/dev/null | cut -f1)"
echo
echo "Setup complete. This job will now exit. Next, from the login node:"
echo "  1. Run your prompts as a batch job (preferred):  sbatch examples/batch_inference.sbatch [prompts.jsonl]"
echo "     or, for a SHORT smoke test only (interactive GPU use is discouraged):"
echo "     srun --partition=gpu --qos=gpu --gres=gpu:a100:1 --mem=24G --time=01:00:00 --pty bash"
echo "  2. Then run:  source scripts/start_ollama.sh"
