# Stanage LLM

## Purpose

A minimal, copy-paste example for running open-weight LLMs (Llama, Qwen,
Mistral, gpt-oss, …) on the University of Sheffield's Stanage HPC cluster,
using Ollama inside an Apptainer container. Handles the HPC mechanics (SLURM,
GPUs, containers, fastdata placement) so users go from "I have a Stanage
account" to "I'm chatting with a model on an A100" in a few commands.

## Repository Layout

```
config/env.sh              # single source of truth: paths, model, host — sourced by every script
scripts/00_setup.sh        # one-time, login node: pulls container image + model weights
scripts/start_ollama.sh    # sourced (not run) on a GPU node: starts server, defines `chat`/`stop_ollama`
scripts/stop_ollama.sh     # stops the server
examples/                  # optional extras: Python API client, batch SLURM job, sample prompts
```

## Key Tooling

- No package manager — plain bash + Python 3 standard library (Python scripts
  optionally use the `openai` client if installed, but fall back gracefully).
- Apptainer is preinstalled on Stanage; there is nothing to build or compile —
  the Ollama image is pulled from Docker Hub.
- All large artifacts (container image, model weights, logs, batch results)
  live under `/mnt/parscratch/users/$USER`, never under home (50 GB quota).

## Verification

There is no test suite — this is a shell/SLURM example repo. To verify a
change:

1. Shellcheck any modified script: `shellcheck scripts/*.sh`
2. Confirm scripts still source `config/env.sh` correctly and don't hardcode
   paths that should come from it.
3. If touching SLURM directives in `examples/batch_inference.sbatch`, sanity
   check against [Stanage SLURM docs](https://docs.hpc.shef.ac.uk/en/latest/hpc/scheduler/index.html)
   — this can't be run outside Stanage.

## Notes

- `start_ollama.sh` must be **sourced**, not executed — it exports env vars
  and shell functions (`chat`, `stop_ollama`) into the calling shell.
- Model choice flows through `MODEL`, set in `config/env.sh` or overridden via
  env var — don't hardcode a model name in a script.
