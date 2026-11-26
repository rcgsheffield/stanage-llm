# Stanage LLM

## Purpose

A set of minimal, copy-paste examples for running open-weight LLMs (Llama,
Qwen, Mistral, gpt-oss, …) on the University of Sheffield's Stanage HPC
cluster. Each example handles the HPC mechanics (SLURM, GPUs, containers,
fastdata placement) for one way of working: `ollama/` (interactive server and
simple batch job) and `workflows/` (workflow engines: Snakemake + vLLM now,
Nextflow / CWL later). The top-level README holds only general information.

## HPC usage

_All_ scripts **must** follow the user guidance described on the [Stanage HPC documentation site](https://docs.hpc.shef.ac.uk/en/latest/hpc/index.html).
Always search this website for authoritative instructions on using the task scheduler, utilising software packages, filestores, etc. etc.

## Repository Layout

```
README.md                  general HPC-LLM info only (no example-specific material)
common/common.sh           shared: fastdata paths, Apptainer cache, SLURM-job check
common/data/prompts.jsonl  shared sample prompts
ollama/                    Ollama example: README.md, config.sh (sourced by the scripts),
                           scripts/{00_setup,start_ollama,stop_ollama}.sh, examples/ (API client, batch job)
workflows/README.md        conventions for workflow-engine examples
workflows/snakemake-vllm/  Snakemake (SLURM plugin) + vLLM offline engine, one GPU job per shard;
                           config.sh, run_workflow.sbatch, every rule runs in the pinned VLLM_IMAGE SIF
```

Each example owns its config, scripts and README and depends only on `common/`.
Scripts and `sbatch` files are submitted from the repo root.

## Key Tooling

- No package manager for the Ollama path — plain bash + Python 3 standard
  library (Python scripts optionally use the `openai` client if installed, but
  fall back gracefully). The vLLM workflow's controller env (Snakemake + SLURM
  plugin) is pinned in `workflows/snakemake-vllm/requirements.txt`; vLLM itself
  comes only from the container.
- Apptainer is preinstalled on Stanage **worker nodes only** (not login
  nodes), so every script that calls it must run inside a SLURM job; there is
  nothing to build or compile —
  the Ollama image is pulled from Docker Hub.
- All large artifacts (container image, model weights, logs, batch results)
  live under `/mnt/parscratch/users/$USER`, never under home (50 GB quota).

## Verification

There is no test suite — this is a shell/SLURM example repo. To verify a
change:

1. Shellcheck any modified script: `shellcheck $(git ls-files '*.sh')`. Lint Python
   with `ruff check .` and workflows with `actionlint`. CI also runs
   these, plus a `CITATION.cff` validation and a lychee Markdown link check.
   For `workflows/snakemake-vllm/`, CI also runs `snakefmt --check`,
   `snakemake --lint` and a profile dry run (`-n`). Locally, export stand-in
   `VLLM_DIR`/`VLLM_SIF`/`HF_HOME` values first; the dry run also needs an
   `apptainer` on PATH (a stub is fine, see `.github/workflows/snakemake.yml`).
2. Confirm scripts still source `ollama/config.sh` correctly and don't hardcode
   paths that should come from it.
3. If touching SLURM directives in `ollama/examples/batch_inference.sbatch`, sanity
   check against [Stanage SLURM docs](https://docs.hpc.shef.ac.uk/en/latest/hpc/scheduler/index.html)
   — this can't be run outside Stanage.

## Notes

- `start_ollama.sh` must be **sourced**, not executed — it exports env vars
  and shell functions (`chat`, `stop_ollama`) into the calling shell.
- Model choice flows through `MODEL`, set in `ollama/config.sh` or overridden via
  env var — don't hardcode a model name in a script.

## Releases

Versioning and the CHANGELOG are automated by
[release-please](https://github.com/googleapis/release-please) (see
`.github/workflows/release.yml`, `release-please-config.json`,
`.release-please-manifest.json`). It only detects version bumps from
[Conventional Commits](https://www.conventionalcommits.org/) — prefix commit
messages / PR titles with `feat:` or `fix:` to trigger a release, `chore:`,
`docs:`, `refactor:` etc. for changes that shouldn't bump the version.

On push to `main`, release-please opens/updates a `chore(main): release
x.y.z` PR with the changelog. Merging that PR tags a GitHub Release, which
triggers `.github/workflows/release-to-orda.yml` to archive the release
tarball to ORDA (Figshare) via the `FIGSHARE_ARTICLE_ID` repo variable and
`FIGSHARE_TOKEN` secret.
