#!/usr/bin/env python3
"""Concatenate per-shard results and write run metadata for provenance.

Usage:
    python3 merge.py OUT.jsonl METADATA.json MODEL.json SETTINGS_JSON SHARD_0.jsonl [...]

Shards are concatenated in the order given (= input order), so results.jsonl
lines up with the input file. MODEL.json (from download_model.py) gives the
exact model commit; SETTINGS_JSON is the run's settings as a JSON string
(sampling, vLLM args, container image, git commit). Both are recorded
alongside a token-usage summary.

Standard library only.
"""

import json
import sys
from datetime import UTC, datetime
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 6:
        sys.exit(__doc__)
    out, meta = Path(sys.argv[1]), Path(sys.argv[2])
    model_info = json.loads(Path(sys.argv[3]).read_text())
    settings, shards = json.loads(sys.argv[4]), sys.argv[5:]

    n = prompt_tokens = completion_tokens = 0
    finish = {}
    tmp = out.with_suffix(out.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fout:
        for shard in shards:
            with open(shard, encoding="utf-8") as fin:
                for line in fin:
                    rec = json.loads(line)
                    n += 1
                    prompt_tokens += rec.get("prompt_tokens") or 0
                    completion_tokens += rec.get("completion_tokens") or 0
                    reason = rec.get("finish_reason")
                    finish[reason] = finish.get(reason, 0) + 1
                    fout.write(line)
    tmp.replace(out)

    meta.write_text(json.dumps({
        "created": datetime.now(UTC).isoformat(timespec="seconds"),
        "n_records": n,
        "n_shards": len(shards),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "finish_reasons": finish,
        "model": model_info,
        **settings,
    }, indent=2) + "\n")

    print(f"Merged {n} results from {len(shards)} shard(s) into {out}")
    if finish.get("length"):
        print(f"NOTE: {finish['length']} response(s) hit max_tokens and were truncated.")


if __name__ == "__main__":
    main()
