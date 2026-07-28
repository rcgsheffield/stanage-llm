# shellcheck shell=bash
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
#   srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --time=08:00:00 --pty bash
#
# Refuses to run outside a SLURM job (i.e. on a login node) -- see
# _check_running_in_slurm_job below.
#
# This script is written to be safe to `source`: it does not enable `set -e`
# (which would kill your interactive shell on any error) and cleans up after
# itself via the `stop_ollama` helper.

# Login nodes are shared and not meant for sustained compute; refuse to start
# the server there. SLURM_JOB_ID is set by both srun and sbatch, and unset on
# a bare login-node shell, so its absence is a reliable "not in a job" signal.
# Override with STANAGE_ALLOW_NO_SLURM=1 for local/off-Stanage testing.
_check_running_in_slurm_job() {
  if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    return 0
  fi
  if [[ "${STANAGE_ALLOW_NO_SLURM:-0}" == "1" ]]; then
    echo "WARNING: no SLURM_JOB_ID detected, but continuing because" >&2
    echo "         STANAGE_ALLOW_NO_SLURM=1." >&2
    return 0
  fi
  echo "ERROR: no active SLURM job detected (SLURM_JOB_ID is unset)." >&2
  echo "       This script must be sourced inside an interactive GPU session," >&2
  echo "       not on a login node. Get one with:" >&2
  echo "         srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --time=08:00:00 --pty bash" >&2
  echo "       Set STANAGE_ALLOW_NO_SLURM=1 to override (e.g. local testing)." >&2
  return 1
}

_check_running_in_slurm_job || return 1 2>/dev/null || exit 1

# Resolve repo root whether sourced from repo root or from scripts/.
_STANAGE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STANAGE_ROOT="$(cd "$_STANAGE_HERE/.." && pwd)"
# shellcheck source=../config/env.sh
source "$_STANAGE_ROOT/config/env.sh"

_check_ollama_host_loopback || return 1 2>/dev/null || exit 1

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

# Scope the log by job id (or PID outside a SLURM job) so concurrent
# interactive sessions/batch jobs don't clobber each other's log.
export OLLAMA_LOG="$OLLAMA_DIR/server.${SLURM_JOB_ID:-$$}.log"

echo "==> Starting Ollama server (model: $MODEL) ..."
_ollama serve >"$OLLAMA_LOG" 2>&1 &
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
  echo "ERROR: server did not start. See $OLLAMA_LOG" >&2
  return 1 2>/dev/null || exit 1
fi

# Convenience helpers for the interactive session.
chat() { _ollama run "$MODEL" "$@"; }
stop_ollama() { bash "$_STANAGE_ROOT/scripts/stop_ollama.sh"; }

# Idle watchdog (on by default, opt out with OLLAMA_IDLE_TIMEOUT=0): if
# nothing has hit the Ollama API for $OLLAMA_IDLE_TIMEOUT minutes, stop the
# server and (under SLURM) cancel the job so the GPU is released even if the
# user walked away. $OLLAMA_LOG's mtime is used as the activity signal -- the
# server logs every API request it handles, so a stale log means an idle
# session.
_start_idle_watchdog() {
  local timeout_s=$(( OLLAMA_IDLE_TIMEOUT * 60 ))
  (
    while kill -0 "$OLLAMA_SERVER_PID" 2>/dev/null; do
      sleep 60
      local last idle
      last=$(stat -c %Y "$OLLAMA_LOG" 2>/dev/null || echo 0)
      idle=$(( $(date +%s) - last ))
      if (( idle >= timeout_s )); then
        {
          echo "==> No Ollama activity for ${OLLAMA_IDLE_TIMEOUT}m -- stopping server."
          [[ -n "${SLURM_JOB_ID:-}" ]] && echo "==> Cancelling SLURM job $SLURM_JOB_ID to release the GPU."
        } | tee -a "$OLLAMA_LOG" >&2
        pkill -f "ollama serve" 2>/dev/null
        [[ -n "${SLURM_JOB_ID:-}" ]] && scancel "$SLURM_JOB_ID"
        break
      fi
    done
  ) &
  export OLLAMA_WATCHDOG_PID=$!
}

echo "==> Ready. The API is at http://$OLLAMA_HOST"
echo "    chat                 # interactive chat with $MODEL"
echo '    chat "your prompt"   # single prompt'
echo "    stop_ollama          # stop the server when you are done"
echo "    Log: $OLLAMA_LOG"

if [[ "${OLLAMA_IDLE_TIMEOUT:-0}" -gt 0 ]]; then
  _start_idle_watchdog
  echo "    Idle watchdog active: auto-quit after ${OLLAMA_IDLE_TIMEOUT}m with no activity."
fi
