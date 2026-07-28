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
# security: it does NOT make the API private to your job. Separately, the HPC
# service must not be used for restricted or sensitive data at all -- no
# setting here changes that. See "Security" in README.md.
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

# Warn -- never change anything -- if the fastdata directories holding your
# prompts, completions and server logs are reachable by other users. Fastdata
# is a cluster-wide filesystem, so directory permissions are the only thing
# keeping your files to yourself. See "Who else can see my models and
# prompts?" in README.md.
#
# Unlike the loopback check above this only WARNS and always succeeds: an open
# area can be deliberate (the Stanage docs describe a 755 top-level area with
# public/ and private/ subdirectories), and aborting a running job over it
# would be worse than the warning. Silence it with
# STANAGE_ALLOW_OPEN_FASTDATA=1.
#
# Mode bits only: a POSIX ACL can grant access that `stat -c %a` doesn't show,
# so treat a silent result as a floor, not a guarantee -- `getfacl` is the
# authoritative check. Called by 00_setup.sh and start_ollama.sh.
_check_fastdata_perms() {
  [[ "${STANAGE_ALLOW_OPEN_FASTDATA:-0}" == "1" ]] && return 0

  local mode bad=0

  # Confidentiality. Denying other users the 'x' (search) bit on $OLLAMA_DIR
  # is what makes the modes of the files inside it irrelevant -- a path can
  # only be resolved if every component along it is searchable. So any
  # group/other bit here matters, and 8#77 catches all of them.
  if [[ -d "$OLLAMA_DIR" ]] &&
     mode="$(stat -c %a "$OLLAMA_DIR" 2>/dev/null)" &&
     [[ "$mode" =~ ^[0-7]+$ ]] && (( 8#$mode & 8#77 )); then
    echo "WARNING: $OLLAMA_DIR is mode $mode -- readable by other users." >&2
    echo "         The server log and any batch results kept there contain" >&2
    echo "         your prompts and completions in plaintext. Make it" >&2
    echo "         private with:" >&2
    echo "           chmod 700 '$OLLAMA_DIR' && chmod -R go-rwx '$OLLAMA_DIR'" >&2
    echo "         or re-run 'STANAGE_FIX_PERMS=1 bash scripts/00_setup.sh'." >&2
    echo "         That stops FUTURE reads only -- it cannot un-share" >&2
    echo "         anything another user has already copied." >&2
    bad=1
  fi

  # Integrity. A group/other-WRITABLE parent lets another user rename or
  # replace directories inside it even when they cannot read them, because
  # rename() needs only write+search on the parent.
  if [[ -d "$PARSCRATCH" ]] &&
     mode="$(stat -c %a "$PARSCRATCH" 2>/dev/null)" &&
     [[ "$mode" =~ ^[0-7]+$ ]] && (( 8#$mode & 8#22 )); then
    echo "WARNING: $PARSCRATCH is mode $mode -- writable by other users, who" >&2
    echo "         could rename or replace directories inside it." >&2
    bad=1
  fi

  if (( bad )); then
    echo "         Silence this check with STANAGE_ALLOW_OPEN_FASTDATA=1." >&2
  fi
  return 0
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
