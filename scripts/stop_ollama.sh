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

# Stop the idle watchdog first so it can't fire (and scancel the job) after
# we've already stopped the server manually.
if [[ -n "${OLLAMA_WATCHDOG_PID:-}" ]] && kill -0 "$OLLAMA_WATCHDOG_PID" 2>/dev/null; then
  kill "$OLLAMA_WATCHDOG_PID" 2>/dev/null
fi

# Stop the server process(es) carrying THIS session's tag (exported by
# start_ollama.sh). Never use an unscoped match on 'ollama serve' -- on a
# shared node another concurrent job of yours may be running its own
# server, and an unscoped pkill would kill that too.
if [[ -n "${OLLAMA_STANAGE_TAG:-}" ]]; then
  _STANAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=../config/env.sh
  source "$_STANAGE_ROOT/config/env.sh"
  for pid in $(_ollama_session_server_pids "$OLLAMA_STANAGE_TAG"); do
    kill "$pid" 2>/dev/null && stopped=1
  done
fi

# Also tidy up the bash subshell wrapping `apptainer exec`. On its own this
# does NOT stop the server (see _ollama_session_server_pids), so it doesn't
# count as "stopped".
if [[ -n "${OLLAMA_SERVER_PID:-}" ]]; then
  kill "$OLLAMA_SERVER_PID" 2>/dev/null
fi

if [[ "$stopped" == "1" ]]; then
  echo "==> Ollama server stopped."
else
  echo "==> No running Ollama server found for this session (nothing to stop)."
  echo "    (If you believe a server is still running, check 'ps' manually --"
  echo "    stop_ollama only stops the server started in this session.)"
fi
