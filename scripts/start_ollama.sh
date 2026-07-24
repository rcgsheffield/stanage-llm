# Start the Ollama server inside the container, on a GPU node.
#
# Run this INSIDE an interactive GPU session, and SOURCE it (don't execute it)
# so the server keeps running in your shell and you get the `chat` helper:
#
#   source scripts/start_ollama.sh
#   chat                       # opens an interactive chat with $MODEL
#   chat "Summarise this: ..."  # or send a one-off prompt
#
# Get a GPU session first with:
#   srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --pty bash
#
# This script is written to be safe to `source`: it does not enable `set -e`
# (which would kill your interactive shell on any error) and cleans up after
# itself via the `stop_ollama` helper.

# Resolve repo root whether sourced from repo root or from scripts/.
_STANAGE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STANAGE_ROOT="$(cd "$_STANAGE_HERE/.." && pwd)"
# shellcheck source=../config/env.sh
source "$_STANAGE_ROOT/config/env.sh"

# The command prefix shared by the server and the client. --nv exposes the
# GPU; -B mounts fastdata (home is auto-mounted, parscratch is not).
_ollama() {
  apptainer exec --nv -B /mnt/parscratch \
    --env OLLAMA_MODELS="$OLLAMA_MODELS" \
    --env OLLAMA_HOST="$OLLAMA_HOST" \
    "$OLLAMA_SIF" ollama "$@"
}

if [[ ! -f "$OLLAMA_SIF" ]]; then
  echo "ERROR: container image not found at $OLLAMA_SIF" >&2
  echo "       Run 'bash scripts/00_setup.sh' on a login node first." >&2
  return 1 2>/dev/null || exit 1
fi

# Confirm we actually have a GPU (catches forgetting --gres / wrong node).
if ! apptainer exec --nv "$OLLAMA_SIF" nvidia-smi >/dev/null 2>&1; then
  echo "WARNING: no GPU visible. Are you in a GPU session (srun ... --gres=gpu:1)?" >&2
  echo "         Continuing on CPU -- this will be very slow." >&2
fi

echo "==> Starting Ollama server (model: $MODEL) ..."
_ollama serve >"$OLLAMA_DIR/server.log" 2>&1 &
export OLLAMA_SERVER_PID=$!

echo -n "==> Waiting for server to be ready"
_ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://$OLLAMA_HOST" >/dev/null 2>&1; then _ready=1; break; fi
  echo -n "."
  sleep 1
done
echo
if [[ "$_ready" != "1" ]]; then
  echo "ERROR: server did not start. See $OLLAMA_DIR/server.log" >&2
  return 1 2>/dev/null || exit 1
fi

# Convenience helpers for the interactive session.
chat() { _ollama run "$MODEL" "$@"; }
stop_ollama() { bash "$_STANAGE_ROOT/scripts/stop_ollama.sh"; }

echo "==> Ready. The API is at http://$OLLAMA_HOST"
echo "    chat                 # interactive chat with $MODEL"
echo '    chat "your prompt"   # single prompt'
echo "    stop_ollama          # stop the server when you are done"
