#!/usr/bin/env bash
#
# Stop the Ollama server started by start_ollama.sh.
#
#   bash scripts/stop_ollama.sh        (or just `stop_ollama` if you sourced start_ollama.sh)
#
# When you then `exit` the interactive session, the GPU is released back to
# the scheduler.

set -uo pipefail

stopped=0

# Prefer the PID exported by start_ollama.sh if it is still around.
if [[ -n "${OLLAMA_SERVER_PID:-}" ]] && kill -0 "$OLLAMA_SERVER_PID" 2>/dev/null; then
  kill "$OLLAMA_SERVER_PID" 2>/dev/null && stopped=1
fi

# Fall back to matching the server process (scoped to 'ollama serve').
if pkill -f "ollama serve" 2>/dev/null; then
  stopped=1
fi

if [[ "$stopped" == "1" ]]; then
  echo "==> Ollama server stopped."
else
  echo "==> No running Ollama server found (nothing to stop)."
fi
