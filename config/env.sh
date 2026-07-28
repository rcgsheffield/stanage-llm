#!/usr/bin/env bash
# Shared configuration for running an open-weight LLM on Stanage with Ollama.
#
# This file is *sourced* by the other scripts (and by you, if you want the
# variables in your own shell). It is the ONE place you need to edit.
#
#   source config/env.sh
#
# The only thing most people change is MODEL (see the table in README.md).
# Override it without editing the file:
#
#   MODEL=qwen2.5:14b source config/env.sh

# --- Where everything lives -------------------------------------------------
# Fastdata (/mnt/parscratch) has no quota, is fast (Lustre), and is reachable
# from BOTH the login node and the worker/GPU nodes. Your home directory
# (/users/$USER) is only 50 GB, so model weights and the container image must
# NOT go there.
export PARSCRATCH="/mnt/parscratch/users/$USER"
export OLLAMA_DIR="$PARSCRATCH/ollama"

# Ollama stores downloaded model weights here. Pointing OLLAMA_MODELS at
# fastdata is what keeps multi-GB models off your 50 GB home quota.
export OLLAMA_MODELS="$OLLAMA_DIR/models"

# The Apptainer image we pull once from Docker Hub.
export OLLAMA_SIF="$OLLAMA_DIR/ollama.sif"

# Pinned to a specific digest (not ":latest" and not "tag@digest" -- Apptainer
# rejects references that combine both) so every pull is reproducible and
# isn't silently swapped out by an upstream retag. Bump this -- and delete
# OLLAMA_SIF so 00_setup.sh re-pulls -- when you want a newer Ollama version
# (0.32.3 as of writing). Find current tags/digests at
# https://hub.docker.com/r/ollama/ollama/tags
export OLLAMA_IMAGE="docker://ollama/ollama@sha256:ec24bcaa2a810eb74171ce7c517813ef4821ed678988845e8d76cf62467036d4"

# Keep Apptainer's build/pull cache off home too.
export APPTAINER_CACHEDIR="$PARSCRATCH/apptainer/cache"

# Address the Ollama server binds to and clients connect to. Apptainer
# shares the host network (no container network isolation), so client and
# server find each other on localhost — but that's about discovery, not
# security: it does NOT make the API private to your job. See "Security" in
# README.md before relying on this for anything sensitive.
#
# The port is picked per job by asking the OS for a free loopback port,
# rather than hardcoded, so two jobs co-scheduled on the same physical node
# (Stanage doesn't guarantee exclusive node allocation) don't collide on a
# fixed port. This is collision AVOIDANCE only, not a security boundary --
# see "Security" in README.md: a random port doesn't stop a co-located user
# from finding it, since a loopback port scan takes seconds.
_stanage_pick_free_port() {
  python3 - <<'EOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
EOF
}

if [[ -z "${OLLAMA_HOST:-}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    _stanage_port="$(_stanage_pick_free_port)"
  else
    echo "WARNING: python3 not found; falling back to fixed port 11434." >&2
    echo "         Concurrent jobs on the same node may collide." >&2
    _stanage_port=11434
  fi
  export OLLAMA_HOST="127.0.0.1:${_stanage_port}"
fi
unset -f _stanage_pick_free_port
unset _stanage_port

# Refuse (or, with an explicit opt-in, warn and continue) if OLLAMA_HOST has
# been overridden away from loopback. See "Security" in README.md: nothing
# else in this setup stops the (unauthenticated) API from being reached by
# other users on the same node once it's bound beyond 127.0.0.1/::1.
# Called by start_ollama.sh and 00_setup.sh right after sourcing this file.
_check_ollama_host_loopback() {
  local host="${OLLAMA_HOST%:*}"
  host="${host#[}"
  host="${host%]}"
  case "$host" in
    127.0.0.1 | localhost | ::1) return 0 ;;
  esac

  echo "WARNING: OLLAMA_HOST='$OLLAMA_HOST' is not bound to loopback." >&2
  echo "         Ollama's API has NO authentication -- see 'Security' in" >&2
  echo "         README.md. Binding beyond 127.0.0.1/::1 can expose it to" >&2
  echo "         other users on the same node." >&2
  if [[ "${OLLAMA_ALLOW_NONLOOPBACK:-0}" == "1" ]]; then
    echo "         Continuing because OLLAMA_ALLOW_NONLOOPBACK=1." >&2
    return 0
  fi
  echo "         Refusing to start. Set OLLAMA_ALLOW_NONLOOPBACK=1 to override." >&2
  return 1
}

# --- Idle auto-quit ---------------------------------------------------------
# Minutes of no Ollama API activity before start_ollama.sh's watchdog stops
# the server and (if running under SLURM) cancels the job, freeing the GPU
# for other users. On by default (60 min) so idle sessions don't hog shared
# GPUs; set to 0 to disable.
export OLLAMA_IDLE_TIMEOUT="${OLLAMA_IDLE_TIMEOUT:-60}"

# --- Which model to run -----------------------------------------------------
# See the "Choosing a model" table in README.md. gemma3:270m is a tiny,
# near-instant default (~300 MB) good for smoke-testing the setup before
# committing to a bigger download.
export MODEL="${MODEL:-gemma3:270m}"
