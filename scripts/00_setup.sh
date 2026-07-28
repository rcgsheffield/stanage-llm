#!/usr/bin/env bash
#
# ONE-TIME SETUP -- run this ONCE, on a Stanage LOGIN NODE (not in a job).
#
#   bash scripts/00_setup.sh
#
# It does two things, both into fastdata (/mnt/parscratch):
#   1. Pulls the Ollama container image from Docker Hub (~1 GB).
#   2. Pre-downloads your chosen model's weights.
#
# We download here, on the login node, because it reliably has internet
# access and the fastdata area is shared with the GPU nodes. Your later GPU
# job then runs completely offline -- it just reads the local files.
#
# No GPU and no root are needed for this step.

set -euo pipefail

# Resolve the repo root from this script's location, then load config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../config/env.sh
source "$ROOT/config/env.sh"

_check_ollama_host_loopback || exit 1

echo "==> Model to prepare : $MODEL"
echo "==> Fastdata area     : $OLLAMA_DIR"
echo

# --- Sanity checks ----------------------------------------------------------
if ! command -v apptainer >/dev/null 2>&1; then
  echo "ERROR: 'apptainer' not found. Are you on Stanage? It is preinstalled" >&2
  echo "       on the login and worker nodes -- no 'module load' is required." >&2
  exit 1
fi

if [[ ! -d /mnt/parscratch ]]; then
  echo "ERROR: /mnt/parscratch not found. This script must run on Stanage." >&2
  exit 1
fi

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
echo "Setup complete. Next:"
echo "  1. Start an interactive GPU session:"
echo "     srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --time=08:00:00 --pty bash"
echo "  2. Then run:  source scripts/start_ollama.sh"
