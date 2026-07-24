#!/usr/bin/env python3
"""Query the running Ollama server from Python.

Ollama exposes an OpenAI-compatible API, so you can use the standard `openai`
client, pointed at the local server, with any dummy API key. This script uses
that if `openai` is installed, and otherwise falls back to a plain HTTP request
via the standard library -- so it works with zero extra installs.

Usage (inside the GPU session, after `source scripts/start_ollama.sh`):

    python3 examples/query_api.py "Explain diffusion models in two sentences."

The model and server address are read from the environment (set by
config/env.sh): MODEL and OLLAMA_HOST.
"""
import json
import os
import sys
import urllib.request

MODEL = os.environ.get("MODEL", "llama3.1:8b")
HOST = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
BASE_URL = f"http://{HOST}"


def ask_with_openai(prompt: str) -> str:
    """Preferred path: the OpenAI-compatible endpoint."""
    from openai import OpenAI  # imported lazily so the fallback works without it

    client = OpenAI(base_url=f"{BASE_URL}/v1", api_key="ollama")  # key is ignored
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
    )
    return resp.choices[0].message.content


def ask_with_stdlib(prompt: str) -> str:
    """Fallback: hit Ollama's native /api/generate with the standard library."""
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


def ask(prompt: str) -> str:
    try:
        return ask_with_openai(prompt)
    except ImportError:
        return ask_with_stdlib(prompt)


def main() -> int:
    if len(sys.argv) < 2:
        print(f'Usage: python3 {sys.argv[0]} "your prompt"', file=sys.stderr)
        return 1
    prompt = " ".join(sys.argv[1:])
    print(ask(prompt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
