#!/usr/bin/env python3
"""Run one shard of prompts through vLLM's offline engine on a GPU.

Usage (inside the vLLM container, on a GPU node -- the Snakefile does this):
    python3 infer.py SHARD.jsonl OUT.jsonl MODEL.json SETTINGS_JSON

Loads the model ONCE, hands the whole shard to vLLM in a single call (vLLM
schedules it with continuous batching, which is where the throughput comes
from), and writes one result per input record, in input order:

    {"id", "prompt" | "messages", "response", "finish_reason",
     "prompt_tokens", "completion_tokens"}

MODEL.json comes from download_model.py and pins the exact commit SHA. The
weights are read from $HF_HOME with HF_HUB_OFFLINE=1, so this never touches
the network.
"""

import json
import sys
import time
from pathlib import Path


def to_messages(rec: dict, system_prompt: str | None) -> list[dict]:
    if isinstance(rec.get("messages"), list):
        return rec["messages"]
    msgs = []
    system = rec.get("system", system_prompt)
    if system:
        msgs.append({"role": "system", "content": system})
    msgs.append({"role": "user", "content": rec["prompt"]})
    return msgs


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    shard, out = Path(sys.argv[1]), Path(sys.argv[2])
    model_info = json.loads(Path(sys.argv[3]).read_text())
    settings = json.loads(sys.argv[4])

    from vllm import LLM, SamplingParams

    records = [json.loads(line) for line in shard.open(encoding="utf-8") if line.strip()]
    conversations = [to_messages(r, settings.get("system_prompt")) for r in records]

    sampling_kwargs = dict(settings["sampling"])
    if settings.get("json_schema"):
        from vllm.sampling_params import StructuredOutputsParams

        sampling_kwargs["structured_outputs"] = StructuredOutputsParams(
            json=settings["json_schema"]
        )
    sampling = SamplingParams(**sampling_kwargs)

    engine_kwargs = dict(settings["vllm"])
    if settings["sampling"].get("seed") is not None:
        engine_kwargs["seed"] = settings["sampling"]["seed"]

    t0 = time.monotonic()
    llm = LLM(
        model=model_info["model"],
        revision=model_info["sha"],
        tokenizer_revision=model_info["sha"],
        tensor_parallel_size=settings["n_gpus"],
        **engine_kwargs,
    )
    t_load = time.monotonic() - t0

    t0 = time.monotonic()
    outputs = llm.chat(conversations, sampling, use_tqdm=True)
    t_gen = time.monotonic() - t0

    n_out_tokens = 0
    tmp = out.with_suffix(out.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        for rec, res in zip(records, outputs, strict=True):
            completion = res.outputs[0]
            n_out_tokens += len(completion.token_ids)
            result = {"id": rec["id"]}
            result["messages" if "messages" in rec else "prompt"] = (
                rec.get("messages", rec.get("prompt"))
            )
            result.update(
                response=completion.text,
                finish_reason=completion.finish_reason,
                prompt_tokens=len(res.prompt_token_ids or []),
                completion_tokens=len(completion.token_ids),
            )
            f.write(json.dumps(result, ensure_ascii=False) + "\n")
    tmp.replace(out)

    print(
        f"{len(records)} prompts | model load {t_load:.0f}s | generation "
        f"{t_gen:.0f}s | {n_out_tokens / max(t_gen, 1e-9):.0f} output tok/s",
        flush=True,
    )


if __name__ == "__main__":
    main()
