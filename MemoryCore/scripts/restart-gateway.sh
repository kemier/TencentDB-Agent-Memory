#!/usr/bin/env bash
# restart-gateway.sh — restart the MemoryCore gateway (8420) preserving its env.
#
# The running gateway's env is dumped to /tmp/gateway-env.txt (by whoever
# captured it); this script restarts with the SAME cwd/command/env so the
# LLM config (TDAI_LLM_BASE_URL/API_KEY/MODEL) and everything else is kept.
# It also refreshes run/memory-core.pid and waits for /health.
#
# Usage: bash scripts/restart-gateway.sh

set -euo pipefail

C=/workspace/git/ezennin/TencentDB-Agent-Memory/MemoryCore
R=/workspace/git/ezennin/TencentDB-Agent-Memory/run
ENV_DUMP=/tmp/gateway-env.txt
PORT=8420
LOG=/tmp/gateway-restart-$(date +%Y%m%d-%H%M%S).log
NODE_HOME="${GATEWAY_NODE_HOME:-${HOME}/.local/lib/node-v22.23.2}"

echo "== 1. capture current listener pid on :$PORT =="
OLD=$(ss -tlnp 2>/dev/null | grep "[:.]${PORT}\b" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
echo "old pid: ${OLD:-none}"

echo "== 2. stop old gateway =="
if [[ -n "$OLD" ]]; then
  kill "$OLD" 2>/dev/null || true
  for i in $(seq 1 15); do
    if ! kill -0 "$OLD" 2>/dev/null; then break; fi
    sleep 0.5
  done
  echo "stopped $OLD"
fi

echo "== 3. launch new gateway with same env (detached) =="
cd "$C"
# Only carry over the gateway-relevant env vars (TDAI_*, STATE_BACKEND,
# COS_*, REDIS_*, LANGFUSE_*, KAFKA_METRIC_*, OTEL_*, SHARK_*, SCANNER_*,
# CLICKHOUSE_*) — the captured dump also contains noisy shell/VS Code vars
# (GUESTFISH_PS1, BASH_FUNC_*, VSCODE_NLS_CONFIG) that break naive sourcing.
python3 - "$ENV_DUMP" "$PWD" <<'PYEOF' > /tmp/gateway-env-export.sh
import re, sys
raw = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
keep = re.compile(
    r'^(TDAI_|STATE_BACKEND|COS_|REDIS_|LANGFUSE_|KAFKA_METRIC_|OTEL_'
    r'|SHARK_|SCANNER_|CLICKHOUSE_|KNOWLEDGE_|TENCENTDB_|MEMORY_)'
)
for line in raw.splitlines():
    if '=' in line and keep.match(line):
        k, _, v = line.partition('=')
        # leave as bare export; values here are simple (no quotes/newlines)
        print(f"export {k}={v}")
PYEOF
set -a
# shellcheck disable=SC1090
source /tmp/gateway-env-export.sh
set +a

# Launch with the FTS5-capable node (system node 22.15.1 lacks node:sqlite
# FTS5 → skill store schema init fails → skill module reports "not enabled").
if [[ ! -x "${NODE_HOME}/bin/node" ]]; then
  echo "error: FTS5-capable node not found at ${NODE_HOME}/bin/node (set GATEWAY_NODE_HOME)" >&2
  exit 1
fi
export PATH="${NODE_HOME}/bin:${PATH}"

setsid nohup "${NODE_HOME}/bin/node" --import tsx src/gateway/server.ts >>"$LOG" 2>&1 </dev/null &
disown 2>/dev/null || true
echo "launched (log: $LOG)"

echo "== 4. wait for health on :$PORT (up to 30s) =="
for i in $(seq 1 30); do
  if curl -sf -m 1 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    NEW=$(ss -tlnp 2>/dev/null | grep "[:.]${PORT}\b" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    mkdir -p "$R"
    echo "${NEW:-unknown}" > "$R/memory-core.pid"
    echo "OK — healthy on :$PORT pid=${NEW:-unknown} (pidfile refreshed)"
    echo "log: $LOG"
    exit 0
  fi
  sleep 1
done

echo "error: gateway not healthy within 30s — tail $LOG" >&2
tail -30 "$LOG" >&2 || true
exit 1
