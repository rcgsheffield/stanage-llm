# Run an open-weight LLM on Stanage

[![ShellCheck](https://github.com/rcgsheffield/stanage-llm/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/rcgsheffield/stanage-llm/actions/workflows/shellcheck.yml)

A minimal, copy-paste example for running open-weight large language models
(Llama, Qwen, Mistral, gpt-oss, …) on the University of Sheffield's
**[Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/index.html)** HPC
cluster — using [Ollama](https://ollama.com) inside an
[Apptainer](https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/apptainer.html) container.

The hard part of doing this isn't the model — it's the HPC mechanics (SLURM,
GPUs, containers, where multi-GB weights are allowed to live). This repo
handles all of that so you can get from *"I have a Stanage account"* to
*"I'm chatting with a model on an A100"* in about five commands.

## Why this approach

- **Ollama** is the simplest way to run a model: one program, it downloads
  quantized models for you, and it serves a local API.
- **Apptainer** is preinstalled on Stanage and needs no root — we *pull* a
  ready-made image, so there is nothing to build or compile.
- **No dependency hell:** the container already contains CUDA, the GPU
  runtime, and Ollama.

## Security

> [!WARNING]
> Ollama's API has **no authentication** — anyone who can reach the port can
> use the model and read/write server state. Binding to `127.0.0.1` (the
> default here) only means the API isn't reachable from *other* nodes; it
> does **not** mean it's private to your job:
>
> - Apptainer shares the host's network namespace (no container network
>   isolation), so `127.0.0.1` inside the container is the same loopback
>   interface as the bare-metal node.
> - These example jobs don't request exclusive node allocation, so another
>   user's job can be co-scheduled on the same physical node — and,
>   depending on the cluster's SSH policy, other users may also be able to
>   log into that node directly, whether or not they have a job running on
>   it.
> - Either way, anyone who can reach that node's loopback interface can
>   reach your Ollama server with no credentials required.
>
> Don't run anything sensitive or confidential through this setup as
> configured. If that matters for your use case, check with [Research
> Computing Support](https://docs.hpc.shef.ac.uk/en/latest/help.html#gsc.tab=0)
> about node exclusivity and SSH access policy on Stanage before
> relying on `127.0.0.1` binding for isolation.
>
> `start_ollama.sh` and `00_setup.sh` enforce this: if `OLLAMA_HOST` is
> overridden away from `127.0.0.1`/`localhost`/`::1`, they print a warning and
> refuse to start. Set `OLLAMA_ALLOW_NONLOOPBACK=1` to override at your own
> risk.

## Prerequisites

- A Stanage account and the ability to log in:
  `ssh $USER@stanage.shef.ac.uk`
  (see [Connecting](https://docs.hpc.shef.ac.uk/en/latest/hpc/connecting.html)).
- That's it. Apptainer is already on every node.

---

## Quick start

### 1. Get the code and configure

On a **login node**:

```bash
git clone <this-repo-url> stanage-llm
cd stanage-llm
```

The only file you might edit is [`config/env.sh`](config/env.sh) — mainly to
pick a different model (see [Choosing a model](#choosing-a-model)). Everything
large (the container image, model weights, logs, results) is stored under
`/mnt/parscratch/users/$USER` — Stanage's *fastdata* area — because your home
directory is capped at **50 GB** and fastdata is uncapped, fast, and visible
from the GPU nodes.

### 2. One-time setup (login node)

```bash
bash scripts/00_setup.sh
```

This pulls the Ollama container image (~1 GB) and pre-downloads your model's
weights into fastdata. We do this **on the login node on purpose**: it has
reliable internet, and the files it writes are readable by the GPU nodes — so
your actual GPU job runs completely offline. Re-running is safe; it skips work
already done.

### 3. Grab a GPU

```bash
srun --partition=gpu --qos=gpu --gres=gpu:1 --mem=82G --pty bash
```

This drops you into an interactive shell on a GPU node with one **A100 (80 GB)**.
For the newer **H100** nodes use `--partition=gpu-h100` instead. Interactive
sessions can run for up to **8 hours**. `--qos=gpu` is required.

### 4. Start the model and chat

Still in the GPU session, from the repo directory:

```bash
source scripts/start_ollama.sh
chat                              # interactive chat
chat "Explain PCA in two sentences."   # or a one-off prompt
```

`source` (not `bash`) matters — it starts the server in your shell and gives
you the `chat` and `stop_ollama` helpers.

### 5. Finish up

```bash
stop_ollama    # stop the server
exit           # leave the GPU session -> releases the GPU to others
```

---

## Choosing a model

Set `MODEL` before running the setup and start scripts. On a single 80 GB
A100 you have plenty of room:

| `MODEL`           | Size (quantized) | Good for                              |
| ----------------- | ---------------- | ------------------------------------- |
| `llama3.1:8b`     | ~5 GB            | Fast default, general chat            |
| `qwen2.5:14b`     | ~9 GB            | Stronger reasoning, coding            |
| `gpt-oss:20b`     | ~14 GB           | Open-weight, strong general model     |
| `llama3.3:70b`    | ~43 GB           | Highest quality; fits one A100        |

Override the default without editing any file — set it once and it flows
through every script:

```bash
export MODEL=qwen2.5:14b
bash scripts/00_setup.sh          # downloads that model
# ... then in the GPU session:
source scripts/start_ollama.sh
```

Browse the full catalogue at <https://ollama.com/library>.

---

## Going further

Two optional extras live in [`examples/`](examples/):

### Query the API from Python

Ollama serves an **OpenAI-compatible** API on `http://127.0.0.1:11434`, so your
existing code using the `openai` client works with only a changed `base_url`
(see [Security](#security) above for what that binding does and doesn't
protect against). Inside the GPU session, after `source scripts/start_ollama.sh`:

```bash
python examples/query_api.py "Draft a one-line commit message for a bug fix."
```

[`query_api.py`](examples/query_api.py) uses the `openai` client if it is
installed and otherwise falls back to the standard library — so it runs with no
extra installs.

### Batch inference over a dataset (no interaction)

To process a file of prompts unattended, submit the batch job — it requests a
GPU, runs every prompt in [`examples/prompts.jsonl`](examples/prompts.jsonl)
through the model, writes answers to fastdata, and exits. The SLURM output
log itself also lands in `/mnt/parscratch/users/$USER/ollama/` — not the
directory you submitted from — so it stays with the rest of that run's
files:

```bash
sbatch examples/batch_inference.sbatch     # from the repo root, on a login node
squeue --me                                # watch it
```

See [`examples/batch_inference.sbatch`](examples/batch_inference.sbatch) for the
SLURM resource request you'd adapt for larger runs (batch jobs may run up to
96 hours).

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `nvidia-smi` fails / model is very slow | You're not on a GPU or forgot `--nv`. Confirm you started the session with `--gres=gpu:1 --qos=gpu`. |
| `apptainer: command not found` | You're probably not on Stanage. It's preinstalled there — no `module load` needed. |
| `image not found` / `command not found` for the model | Run `bash scripts/00_setup.sh` on a login node first. |
| Out-of-memory / CUDA OOM | Use a smaller `MODEL`, or request more with `--mem` / a bigger GPU (`--partition=gpu-h100-nvl` for 94 GB). |
| First response is slow, then fast | Normal — the weights load from Lustre into VRAM on first use. |
| Home quota full | Confirm `OLLAMA_MODELS` points at `/mnt/parscratch/...` (it does by default). Never let Ollama write to `~/.ollama`. |
| Server won't start | Check the log: `cat /mnt/parscratch/users/$USER/ollama/server.log`. |

---

## How it fits together

```
login node                         GPU node (interactive srun session)
-----------                        -----------------------------------
00_setup.sh                        start_ollama.sh
  apptainer pull ollama.sif  --->    apptainer exec --nv ... ollama serve  (background)
  ollama pull $MODEL         --->    chat  ->  ollama run $MODEL
       |                                          |
       v                                          v
  /mnt/parscratch/users/$USER/ollama   (image + weights, shared by both)
```

## Where your data lives

Stanage has several storage areas with very different rules; this repo only
uses two of them.

| Area | Path | Used for | Notes |
| --- | --- | --- | --- |
| Fastdata | `/mnt/parscratch/users/$USER` | Container image, model weights, server logs, batch job output/results | No quota, no backups. Fast (Lustre) and readable from both login and GPU nodes — the only area both need to see the same files. Not tuned for lots of small files, so don't dump unrelated small-file workloads here. |
| Home | `~` (`/users/$USER`) | This git checkout only | Capped at **50 GB**, not backed up. Everything large is deliberately kept out (see `config/env.sh`) so cloning this repo never risks the quota. |

See [Filestores](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html) for
the full picture, including quotas and backup policy for areas this repo
doesn't touch.

## Reference documentation

- [Using GPUs on Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/GPUComputingStanage.html)
- [Job submission (SLURM)](https://docs.hpc.shef.ac.uk/en/latest/hpc/scheduler/index.html)
- [Apptainer/Singularity on Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/apptainer.html)
- [Filestores (home / fastdata / scratch)](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html)
- [Stanage specifications](https://docs.hpc.shef.ac.uk/en/latest/stanage/cluster_specs.html)

---

![Stanage logo](stanage-logo.png)
