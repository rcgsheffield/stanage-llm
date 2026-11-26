#!/usr/bin/env bash
# Configuration for the vLLM batch workflow (workflows/snakemake-vllm/).
# Sourced by run_workflow.sbatch and scripts/setup.sh. The Ollama scripts do
# not use it. Everything stays on fastdata (see common.sh).
#
#   source workflows/snakemake-vllm/config.sh

_VLLM_CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../common/common.sh
source "$_VLLM_CONF_DIR/../../common/common.sh"
unset _VLLM_CONF_DIR

export VLLM_DIR="$PARSCRATCH/vllm"
# The image is ~10 GB, almost all of it the CUDA/PyTorch stack vLLM needs.
# One big file read by every GPU job is what fastdata is for (no quota); it
# isn't backed up, but setup can always re-pull it. A group can share one copy
# (e.g. under /usr/local/community, the Stanage area for shared software) by
# exporting VLLM_SIF=/path/to/vllm.sif before running anything.
export VLLM_SIF="${VLLM_SIF:-$VLLM_DIR/vllm.sif}"

# Pinned by digest, same convention as OLLAMA_IMAGE. This is the multi-arch
# index digest of vllm/vllm-openai:v0.32.0-cu129 -- the CUDA 12.9 build, which
# runs on a wider range of host NVIDIA drivers than the default CUDA 13 tags.
# Bump it (and delete VLLM_SIF so setup re-pulls) for a newer vLLM. Tags:
# https://hub.docker.com/r/vllm/vllm-openai/tags
export VLLM_IMAGE="docker://vllm/vllm-openai@sha256:bc0445dac61accbf1c3b17fbb524a71eee0b1b32f55ba45952095e3be8991c3f"

# Overlay for a bug in the image above: it ships torchcodec 0.17.0 built for
# CUDA 13 (needs libnvrtc.so.13 / libcudart.so.13), but the image is CUDA 12.9,
# so `import vllm` fails. vLLM's requirements only say `torchcodec >= 0.14`, so
# the image build picked up the CUDA 13 wheel. setup.sh installs this CUDA 12.9
# build of torchcodec (a few MB, --no-deps) into VLLM_OVERLAY_DIR on fastdata,
# and the Snakefile puts that directory first on PYTHONPATH inside the container.
# Drop both once a newer image fixes it (check with `import torchcodec`).
export VLLM_OVERLAY_DIR="$VLLM_DIR/pylibs"
export VLLM_TORCHCODEC_SPEC="${VLLM_TORCHCODEC_SPEC:-torchcodec==0.16.0+cu129}"
export VLLM_TORCHCODEC_INDEX="${VLLM_TORCHCODEC_INDEX:-https://download.pytorch.org/whl/cu129}"

# Python virtual environment (venv) holding Snakemake + its SLURM executor
# plugin (the workflow's controller side; vLLM itself lives in the container).
# Built from the cluster module below; setup and the controller job both load
# it. Snakemake needs Python >= 3.11.
#
# This must be an architecture-independent Python: Snakemake's SLURM plugin
# also runs the venv's Python on the *GPU* nodes (AMD EPYC), while the
# login/CPU nodes are Intel. The `Python/*` modules in the el9 tree are built
# for the Intel CPUs and die with "Illegal instruction" (SIGILL) on the GPU
# nodes, so use Anaconda3, which lives in the arch-independent `common` tree.
# A venv is tied to the interpreter that built it: after changing the module,
# delete $VLLM_ENV and re-run setup.
export VLLM_ENV="$VLLM_DIR/env"
export VLLM_PYTHON_MODULE="${VLLM_PYTHON_MODULE:-Anaconda3/2025.06-1}"

# Load VLLM_PYTHON_MODULE. Batch shells don't always inherit the `module`
# function, so source the init script first if needed.
_load_vllm_python_module() {
  if ! type module >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source /etc/profile.d/modules.sh 2>/dev/null ||
      source /etc/profile.d/lmod.sh 2>/dev/null || true
  fi
  module load "$VLLM_PYTHON_MODULE"
}

# Hugging Face weights cache. vLLM loads safetensors from the HF Hub, not
# Ollama's GGUF blobs, so models are downloaded separately into here.
export HF_HOME="$PARSCRATCH/huggingface"
