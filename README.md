# Running open-weight LLMs on Stanage

[![ShellCheck](https://github.com/rcgsheffield/stanage-llm/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/rcgsheffield/stanage-llm/actions/workflows/shellcheck.yml)
[![DOI](https://img.shields.io/badge/DOI-10.15131%2Fshef.data.33102185-blue)](https://doi.org/10.15131/shef.data.33102185)

> [!WARNING]
> **Experimental — not officially supported.** This is an experimental tool
> and is not an officially supported service of the University of Sheffield
> or its Research IT / HPC teams. Use it at your own risk; it may change or
> break without notice.


Worked, copy-paste examples for running open-weight large language models
(Llama, Qwen, Mistral, gpt-oss, …) on the University of Sheffield's
**[Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/index.html)** HPC
cluster.

The hard part isn't the model — it's the HPC mechanics (SLURM, GPUs,
containers, where multi-GB weights are allowed to live). Each example here
handles those for one way of working, so you can start from something that runs.

> [!CAUTION]
> **The HPC service must not be used to store or process any restricted or
> sensitive data.** This is a rule for Stanage as a whole, not
> just for this repo — no configuration of these scripts, or of anything else
> on the clusters, makes sensitive data acceptable here. Keep to
> non-sensitive, non-personal data — see [Security](#security) for the details
> and what to do if you need more.


## Examples

| Example | Style | Use it for |
| --- | --- | --- |
| [`ollama/`](ollama/README.md) | Ollama server in an Apptainer container; interactive chat and simple batch job | Trying models, prompt iteration, small batches |
| [`workflows/`](workflows/README.md) | Workflow engines that shard a dataset and run one GPU job per shard | Whole datasets (thousands of prompts or more), resumable runs |

Within [`workflows/`](workflows/README.md): [`snakemake-vllm/`](workflows/snakemake-vllm/README.md)
(Snakemake + vLLM). Other engines (Nextflow, Common Workflow Language) can be
added as siblings.

Shared pieces live in [`common/`](common/): fastdata paths and the Apptainer
cache (`common.sh`) and sample prompts (`data/prompts.jsonl`, one
`{"id": "1", "prompt": "..."}` per line).

## Common ground

Every example follows the same conventions:

- **Apptainer containers**, pulled rather than built. Apptainer is installed on
  Stanage's *worker* nodes only, so anything that calls it runs inside a SLURM
  job. Setup steps are small CPU jobs started from the login node.
- **Everything large lives on fastdata**, `/mnt/parscratch/users/$USER`: container
  images, model weights, logs and results. Your home directory is capped at 50 GB.
  See [Where your data lives](#where-your-data-lives).
- **GPU work goes through batch jobs.** Stanage's docs say [interactive GPU use
  is strongly discouraged](https://docs.hpc.shef.ac.uk/en/latest/stanage/GPUComputingStanage.html);
  keep interactive sessions short, and use the documented per-GPU minimum host
  RAM/CPUs. GPU type is chosen with `--gres=gpu:TYPE:1` plus `--qos=gpu`.
- **Run from the repository root.** Scripts and `sbatch` files use paths relative to it.

## Security

The Stanage HPC [filestore documentation](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html#shared-project-directories) states:

> **Danger**
>
> The High Performance Computing service must not be used to store or process
> any restricted or sensitive data. Shared areas with this type of data are not
> permitted to be made available on the clusters.
>
> Research shared storage areas may already contain sensitive data, or may
> contain sensitive data stored by colleagues you are not aware of. Before
> requesting an area to be made available on the HPC clusters, you must ensure
> that they do not and will not contain any sensitive data for the life time of
> the area.

**This isn't specific to this repo.** The prohibition applies to the whole HPC service. The weaknesses described below are additional reasons to be careful — they are not the reason the rule exists, and fixing them would not make processing sensitive data permissible.

If in doubt, don't mount it and don't process it — ask [Research Computing Support](https://docs.hpc.shef.ac.uk/en/latest/help.html) first.

### What data is this suitable for?

Only data you would be comfortable with another Stanage user seeing. In
practice that means public, synthetic, or otherwise non-sensitive material:
open datasets, published text, your own draft writing, code you're happy to
share.

**Do not use these scripts for:**

- personal data / anything identifying a living individual (UK GDPR),
- clinical, patient, or participant data,
- commercially confidential or contractually restricted data (e.g. industry
  partner data, data under an NDA or a data sharing agreement),
- anything above *Public* under the University's [Information Classification
  scheme](https://sheffield.ac.uk/library/records-management-policy-and-guidance),
- anything the University's [research data security
  guidance](https://sheffield.ac.uk/library/research-data-management/security)
  says needs controlled handling,
- exam material, unpublished assessments, or HR/staff records.

If you're unsure which bucket your data falls into, classify it against the
Information Classification scheme *before* you run anything through this setup,
not after.

Each example documents its own additional exposure (for instance, an unauthenticated
local API, or plaintext prompts and results in logs). If your work genuinely needs to process
restricted data, use a service built for it rather than adapting these examples:
the University's [Secure Data
Service](https://students.sheffield.ac.uk/it-services/research/secure-data-service)
is the intended route. Talk to [Research Computing
Support](https://docs.hpc.shef.ac.uk/en/latest/help.html#gsc.tab=0) and your
faculty's information governance contact **before** running anything. Don't
assume an example can be made adequate by tweaking a variable.

### Who else can see my files?

Your files go in a per-user directory on a filesystem shared by the whole
cluster. `/mnt/parscratch` is one Lustre filesystem mounted on every node, and
your `/mnt/parscratch/users/$USER` directory [doesn't exist by
default](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html#fastdata-areas)
and should be created mode `700`. Created under the usual default umask it is
`755` — **readable by every other user.** The setup scripts create the directory
as `700` and warn about existing ones, but never change them silently. Check yourself:

```bash
ls -ld /mnt/parscratch/users/$USER
# want: drwx------
```

Directory permissions keep out other unprivileged users only: they don't hide
anything from administrators, encrypt anything, or make a setup suitable for
restricted data. The Ollama example has the [full
details](ollama/README.md#who-else-can-see-my-models-and-prompts), including the
environment variables that control this.


## Prerequisites

- A Stanage account (see [getting an account](https://docs.hpc.shef.ac.uk/en/latest/hpc/accounts.html)).
- The ability to log in:
  `ssh $USER@stanage.shef.ac.uk`
  (see [Connecting](https://docs.hpc.shef.ac.uk/en/latest/hpc/connecting.html)).
- Clone this repository on a **login node** (it is public, so HTTPS needs no GitHub credentials):

```bash
git clone https://github.com/rcgsheffield/stanage-llm.git
cd stanage-llm
```

Then follow the README of the example you want.

## Where your data lives

Stanage has several storage areas with very different rules; these examples use
two of them.

| Area | Path | Used for | Notes |
| --- | --- | --- | --- |
| Fastdata | `/mnt/parscratch/users/$USER` | Container images, model weights, logs, results | No quota, no backups. Fast (Lustre) and readable from both login and GPU nodes. **A per-user directory on a cluster-wide filesystem: private only because the setup scripts create it mode `700`** ([details](#who-else-can-see-my-files)). Not tuned for lots of small files. |
| Home | `~` (`/users/$USER`) | This git checkout only | Capped at **50 GB**, not backed up. Everything large is kept out so cloning never risks the quota. |

Each example uses its own subdirectory of fastdata (`ollama/`, `vllm/`, …).
Neither area is encrypted at rest or backed up, and everything written to
fastdata is plaintext, including logs and every prompt and completion — another
reason not to run sensitive or confidential data through these examples. See
[Security](#security).

If you bind-mount a shared project directory into a job, the same rule applies
to that area: it must not contain restricted or sensitive data, now or at any
point while it is available on the cluster.

See [Filestores](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html) for
the full picture, including quotas and backup policy.

## Citing this repository

Please cite this repository using the metadata in [`CITATION.cff`](CITATION.cff) (GitHub renders a "Cite this repository" button on the repo homepage from this file), or via its DOI: [10.15131/shef.data.33102185](https://doi.org/10.15131/shef.data.33102185).

If this work made use of Stanage, please also acknowledge the HPC service itself, as recommended in the [Stanage citation guidance](https://docs.hpc.shef.ac.uk/en/latest/citing.html#gsc.tab=0):

> We acknowledge IT Services at The University of Sheffield for the provision of services for High Performance Computing.

## Reference documentation

- [Using GPUs on Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/GPUComputingStanage.html)
- [Job submission (SLURM)](https://docs.hpc.shef.ac.uk/en/latest/hpc/scheduler/index.html)
- [Apptainer/Singularity on Stanage](https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/apptainer.html)
- [Filestores (home / fastdata / scratch)](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html)
- [Shared project directories — including the restricted/sensitive data prohibition](https://docs.hpc.shef.ac.uk/en/latest/hpc/filestore.html#shared-project-directories)
- [Stanage specifications](https://docs.hpc.shef.ac.uk/en/latest/stanage/cluster_specs.html)
- [Information Classification scheme (records management policy and guidance)](https://sheffield.ac.uk/library/records-management-policy-and-guidance)
- [Research data security (University of Sheffield)](https://sheffield.ac.uk/library/research-data-management/security)
- [Secure Data Service — for sensitive research data](https://students.sheffield.ac.uk/it-services/research/secure-data-service)

---

![Stanage logo](stanage-logo.png)

---

## AI Usage Statement

Parts of this repository were written with the assistance of Claude Code, Anthropic's command-line coding agent. AI was used as a tool under human direction, not as an autonomous author. Every change — whether AI-assisted or hand-written — was reviewed, tested, and accepted by a human maintainer before being committed or merged.

