#!/usr/bin/env python3
"""Run a model over a JSONL file of prompts and write a JSONL of results.

Reads records like {"id": "1", "prompt": "..."} and writes
{"id": "1", "prompt": "...", "response": "..."} for each.

Usage:
    python3 examples/batch_infer.py INPUT.jsonl OUTPUT.jsonl

Model and server address come from the environment (MODEL, OLLAMA_HOST),
set by config/env.sh. Uses the `openai` client if available, otherwise the
standard library -- see query_api.py for details.
"""
import json
import os
import sys
import urllib.request

MODEL = os.environ.get("MODEL", "llama3.1:8b")
HOST = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
BASE_URL = f"http://{HOST}"


def ask(prompt: str) -> str:
    try:
        from openai import OpenAI

        client = OpenAI(base_url=f"{BASE_URL}/v1", api_key="ollama")
        resp = client.chat.completions.create(
            model=MODEL, messages=[{"role": "user", "content": prompt}]
        )
        return resp.choices[0].message.content
    except ImportError:
        payload = json.dumps(
            {"model": MODEL, "prompt": prompt, "stream": False}
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{BASE_URL}/api/generate",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())["response"]


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: python3 {sys.argv[0]} INPUT.jsonl OUTPUT.jsonl", file=sys.stderr)
        return 1
    in_path, out_path = sys.argv[1], sys.argv[2]

    error_count = 0
    with open(in_path) as fin, open(out_path, "w") as fout:
        for line_num, line in enumerate(fin, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                record["response"] = ask(record["prompt"])
            except Exception as exc:
                error_count += 1
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    record = {"raw_line": line}
                record["error"] = str(exc)
                fout.write(json.dumps(record) + "\n")
                fout.flush()
                print(
                    f"[error] line={line_num} id={record.get('id', '?')}: {exc}",
                    file=sys.stderr,
                    flush=True,
                )
                continue
            fout.write(json.dumps(record) + "\n")
            fout.flush()
            print(f"[done] id={record.get('id', '?')}", flush=True)

    print(f"Wrote results to {out_path} ({error_count} error(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
