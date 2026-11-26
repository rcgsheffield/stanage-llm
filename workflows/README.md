# Workflow examples

Examples that run an LLM over **a whole dataset** with a workflow engine: split
the input into shards, run one GPU job per shard, merge the results. Finished
shards are kept, so a failed or timed-out run resumes where it stopped.

Read the [top-level README](../README.md) first, especially
[Security](../README.md#security): **no restricted or sensitive data on Stanage.**

| Example | Engine | Inference | Status |
| --- | --- | --- | --- |
| [`snakemake-vllm/`](snakemake-vllm/README.md) | [Snakemake](https://snakemake.readthedocs.io/) + SLURM executor plugin | [vLLM](https://docs.vllm.ai/) offline engine | Available |
| `nextflow-*/` | Nextflow | — | Not yet written |
| `cwl-*/` | Common Workflow Language | — | Not yet written |

For trying models, interactive chat or small batches, the
[Ollama example](../ollama/README.md) is simpler.

## Conventions for a workflow example

- One directory per engine and inference backend, named `<engine>-<backend>`.
  It contains its own `README.md`, `config.sh` (sourced from the repo root, which
  in turn sources [`common/common.sh`](../common/common.sh)), and a controller
  `sbatch` script submitted from the repository root.
- Input is JSONL with `{"id", "prompt"}` per line; see
  [`common/data/prompts.jsonl`](../common/data/prompts.jsonl).
- Every step runs inside a pinned Apptainer image, and everything large lives
  on fastdata under `/mnt/parscratch/users/$USER/<backend>/`.
- Settings shared by several engines (for example the vLLM image and Hugging
  Face cache) should move into a common file in this directory only once a
  second engine needs them.
