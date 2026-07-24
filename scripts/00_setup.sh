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

mkdir -p "$OLLAMA_MODELS" "$APPTAINER_CACHEDIR"

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
echo "==> Starting a temporary Ollama server to download '$MODEL' ..."
apptainer exec \
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
apptainer exec \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama pull "$MODEL"

echo
echo "==> Models now available in $OLLAMA_MODELS:"
apptainer exec \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama list

echo
echo "==> Disk used by models: $(du -sh "$OLLAMA_MODELS" 2>/dev/null | cut -f1)"
echo
echo "Setup complete. Next:"
echo "  1. Start an interactive GPU session:"
echo "     srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --pty bash"
echo "  2. Then run:  source scripts/start_ollama.sh"
