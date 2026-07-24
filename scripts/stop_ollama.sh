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

# Fall back to matching the server process, but ONLY if the PID kill above
# didn't already handle it, and ONLY scoped to this session's own tag
# (exported by start_ollama.sh). Never fall back to an unscoped match on
# 'ollama serve' -- on a shared node another concurrent job of yours may be
# running its own server, and an unscoped pkill would kill that too.
if [[ "$stopped" == "0" ]]; then
  if [[ -n "${OLLAMA_STANAGE_TAG:-}" ]]; then
    if pkill -f "OLLAMA_STANAGE_TAG=${OLLAMA_STANAGE_TAG} .*ollama serve" 2>/dev/null; then
      stopped=1
    fi
  fi
fi

if [[ "$stopped" == "1" ]]; then
  echo "==> Ollama server stopped."
else
  echo "==> No running Ollama server found for this session (nothing to stop)."
  echo "    (If you believe a server is still running, check 'ps' manually --"
  echo "    stop_ollama only stops the server started in this session.)"
fi
