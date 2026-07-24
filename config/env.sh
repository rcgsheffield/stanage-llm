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

# Keep Apptainer's build/pull cache off home too.
export APPTAINER_CACHEDIR="$PARSCRATCH/apptainer/cache"

# Address the Ollama server binds to and clients connect to. The default is
# fine; Apptainer shares the host network, so client and server find each
# other on localhost.
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

# --- Which model to run -----------------------------------------------------
# See the "Choosing a model" table in README.md. llama3.1:8b is a fast,
# well-behaved default that fits comfortably on a single A100.
export MODEL="${MODEL:-llama3.1:8b}"
