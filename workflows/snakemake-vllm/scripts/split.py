#!/usr/bin/env python3
"""Validate a prompts JSONL file and split it into fixed-size shards.

Usage:
    python3 split.py INPUT.jsonl SHARD_SIZE SHARD_0.jsonl [SHARD_1.jsonl ...]

Each input line must be a JSON object with a unique "id" and either a
"prompt" string or a "messages" list (OpenAI chat format). The number of
shard paths must equal ceil(n_records / SHARD_SIZE) -- the Snakefile computes
it the same way.

Standard library only.
"""

import json
import math
import sys
from pathlib import Path


def load_records(path: Path) -> list[dict]:
    records, seen = [], set()
    with path.open(encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as e:
                sys.exit(f"{path}:{lineno}: invalid JSON: {e}")
            if not isinstance(rec, dict) or "id" not in rec:
                sys.exit(f"{path}:{lineno}: each record needs an \"id\" field")
            if not isinstance(rec.get("prompt"), str) and not isinstance(
                rec.get("messages"), list
            ):
                sys.exit(
                    f"{path}:{lineno}: record needs a \"prompt\" string or a "
                    "\"messages\" list"
                )
            rid = str(rec["id"])
            if rid in seen:
                sys.exit(f"{path}:{lineno}: duplicate id {rid!r}")
            seen.add(rid)
            records.append(rec)
    if not records:
        sys.exit(f"{path}: no records found")
    return records


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    src, shard_size, outs = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
    if shard_size < 1:
        sys.exit("SHARD_SIZE must be >= 1")

    records = load_records(src)
    expected = math.ceil(len(records) / shard_size)
    if len(outs) != expected:
        sys.exit(
            f"{len(records)} records / shard_size {shard_size} needs {expected} "
            f"shards, but {len(outs)} output paths were given. Did the input "
            "change after the workflow started? Re-run Snakemake."
        )

    for i, out in enumerate(outs):
        chunk = records[i * shard_size : (i + 1) * shard_size]
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.writelines(json.dumps(rec, ensure_ascii=False) + "\n" for rec in chunk)
    print(f"Split {len(records)} records into {len(outs)} shard(s)")


if __name__ == "__main__":
    main()
