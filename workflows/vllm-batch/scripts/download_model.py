#!/usr/bin/env python3
"""Download a Hugging Face model snapshot into $HF_HOME and record its SHA.

Usage:
    python3 download_model.py MODEL_ID REVISION OUT.json

Runs inside the vLLM container (which ships huggingface_hub) in the CPU
controller job, so the GPU jobs never touch the network: they run with
HF_HUB_OFFLINE=1 and load the exact commit written to OUT.json.

Already-downloaded files are skipped, so re-running is cheap. Gated models
need HF_TOKEN set in the environment; it is read by huggingface_hub and never
written anywhere by this script.
"""

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    model, revision, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])

    try:
        from huggingface_hub import HfApi, snapshot_download
    except ImportError:
        sys.exit("huggingface_hub not found -- is this running in the vLLM container?")

    try:
        sha = HfApi().model_info(model, revision=revision).sha
    except Exception as e:  # noqa: BLE001 -- report any Hub error clearly
        sys.exit(
            f"Could not resolve {model}@{revision} on the Hugging Face Hub: {e}\n"
            "Check the model id and revision. Gated models need HF_TOKEN set "
            "and the licence accepted on huggingface.co."
        )

    print(f"Downloading {model} @ {sha} ...", flush=True)
    path = snapshot_download(
        repo_id=model,
        revision=sha,
        # Only what vLLM needs (*.py: custom tokenizer/model code); skips duplicate .bin/.pth/GGUF/ONNX copies
        # some repos ship alongside the safetensors.
        allow_patterns=["*.json", "*.safetensors", "*.model", "*.txt", "*.tiktoken", "*.jinja", "*.py"],
    )
    if not any(Path(path).glob("*.safetensors")):
        sys.exit(
            f"{model}@{sha} has no .safetensors weights; vLLM needs a "
            "safetensors (Hugging Face Transformers) repo, not GGUF."
        )

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps({"model": model, "revision": revision, "sha": sha}, indent=2) + "\n"
    )
    print(f"Model ready at {path}")


if __name__ == "__main__":
    main()
