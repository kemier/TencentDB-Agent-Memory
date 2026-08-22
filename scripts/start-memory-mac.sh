#!/usr/bin/env bash
# Start Ollama (if installed) and MemoryCore TDAI gateway on Mac for vscode-acp.
#
# Run from Terminal.app so the gateway process survives (IDE sandboxes may kill background jobs):
#   bash /Users/zaedinzeng/projects/TencentDB-Agent-Memory/scripts/start-memory-mac.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/MemoryCore"
CONFIG="$CORE/tdai-gateway.mac.yaml"
LOG="/tmp/memory-core.log"
PIDFILE="/tmp/memory-core.pid"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8420}"

log() { echo "[start-memory-mac] $*"; }

if command -v ollama >/dev/null 2>&1; then
  if ! curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    log "Starting Ollama..."
    if command -v brew >/dev/null 2>&1; then
      brew services start ollama 2>/dev/null || true
    fi
    sleep 2
  fi
  if curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    log "Ollama OK at $OLLAMA_URL"
    # Must match MemoryCore/tdai-gateway.mac.yaml (llm + extraction + embedding).
    for m in qwen3:14b qwen2.5:1.5b-instruct bge-m3; do
      if ! curl -sf "$OLLAMA_URL/api/tags" | grep -q "\"name\":\"$m\""; then
        log "Pulling $m..."
        ollama pull "$m" || log "Warning: failed to pull $m"
      fi
    done
  else
    log "Warning: Ollama not reachable; embeddings may fail — ensure vllm-proxy :8317 for LLM"
  fi
else
  log "Ollama not installed; install with: brew install ollama"
fi

[[ -f "$CONFIG" ]] || { echo "Missing config: $CONFIG" >&2; exit 1; }

cd "$CORE"
if [[ ! -d node_modules ]]; then
  log "npm install..."
  npm install
fi

if [[ -f "$PIDFILE" ]]; then
  old_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" 2>/dev/null; then
    log "Stopping existing gateway pid=$old_pid"
    kill "$old_pid" 2>/dev/null || true
    sleep 1
  fi
fi

export TDAI_GATEWAY_CONFIG="$CONFIG"
export TDAI_GATEWAY_API_KEY="${TDAI_GATEWAY_API_KEY:-local}"
export TDAI_LLM_API_KEY="${TDAI_LLM_API_KEY:-local}"

log "Starting MemoryCore gateway (log=$LOG)..."
nohup node --import tsx src/gateway/server.ts >>"$LOG" 2>&1 &
GATE_PID=$!
echo "$GATE_PID" >"$PIDFILE"
disown "$GATE_PID" 2>/dev/null || true

for i in $(seq 1 30); do
  if curl -sf "$GATEWAY_URL/health" >/dev/null 2>&1; then
    log "Gateway healthy at $GATEWAY_URL (pid=$GATE_PID)"
    curl -s "$GATEWAY_URL/health"
    echo
    exit 0
  fi
  sleep 1
done

log "Gateway failed health check after 30s; tail $LOG"
tail -40 "$LOG" >&2 || true
exit 1
