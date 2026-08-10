#!/usr/bin/env bash
# Start TencentDB Agent Memory services natively (no Docker).
#   memory-core (8420) + knowledge (8424) + proxy (8096)
#
# Usage:
#   ./run/start-local.sh                      # start all 3
#   ./run/start-local.sh memory-core          # start one (or: knowledge | proxy)
#   ./run/start-local.sh knowledge proxy      # start several
#   ./run/start-local.sh --stop               # stop all 3
#   ./run/start-local.sh --stop knowledge     # stop one (or: memory-core | proxy)
#   ./run/start-local.sh --stop knowledge proxy  # stop several
#   ./run/start-local.sh --status             # show live status
#
# NOTE on memory-core: ./run/start-local.sh launches memory-core with the
# run/ data dir (TDAI_DATA_DIR=run/data/memory-core). There is also a
# "live" memory-core instance launched via nohup that uses the default data
# dir (~/.memory-tencentdb/memory-tdai/) and is what the vscode-acp memory
# integration depends on — see AGENTS.md "Preferred memory-core launch".
# Do NOT run two memory-core instances at once (port 8420 clash). If a
# memory-core is already running on 8420, starting it here will fail to
# bind; use --status to check first, or start only `knowledge proxy`.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$REPO/run"
LOGS_DIR="$RUN_DIR/logs"
mkdir -p "$LOGS_DIR" "$RUN_DIR/data"

ALL_SERVICES=(memory-core knowledge proxy)

# Resolve the real (long-lived) node PID for a just-launched service and
# write it to the pid file. `nohup npm run ... &` gives us the npm wrapper
# PID via $!, but npm exits once it has spawned node — so we instead wait
# briefly and grab the node process listening on the service's port.
write_pid() {
  local svc="$1" port="$2" launcher_pid="$3"
  echo "$launcher_pid" > "$RUN_DIR/$svc.pid"   # fallback: npm wrapper
  for _ in $(seq 1 25); do
    sleep 0.4
    local pid
    pid="$(ss -tlnpH 2>/dev/null | grep -E ":$port\b" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2 || true)"
    if [[ -n "$pid" ]]; then
      echo "$pid" > "$RUN_DIR/$svc.pid"
      return 0
    fi
  done
  # Could not resolve listener; keep the wrapper PID and warn.
  echo "  WARNING: $svc did not bind :$port within 10s — check $LOGS_DIR/$svc.log" >&2
}

port_for() { case "$1" in memory-core) echo 8420;; knowledge) echo 8424;; proxy) echo 8096;; esac; }

start_memory_core() {
  echo "Starting memory-core (8420)..."
  cd "$REPO/MemoryCore"
  # LLM endpoint is env-overridable so this script stays provider-agnostic.
  # Set TDAI_LLM_BASE_URL / TDAI_LLM_API_KEY / TDAI_LLM_MODEL before invoking,
  # or copy run/tdai-gateway.yaml.example to run/tdai-gateway.yaml and edit.
  TDAI_GATEWAY_CONFIG="$RUN_DIR/tdai-gateway.yaml" \
  TDAI_GATEWAY_HOST=127.0.0.1 \
  TDAI_GATEWAY_PORT=8420 \
  TDAI_DATA_DIR="$RUN_DIR/data/memory-core" \
  TDAI_LLM_BASE_URL="${TDAI_LLM_BASE_URL:-http://127.0.0.1:8000/v1}" \
  TDAI_LLM_API_KEY="${TDAI_LLM_API_KEY:-}" \
  TDAI_LLM_MODEL="${TDAI_LLM_MODEL:-gpt-4o-mini}" \
    nohup node --import tsx src/gateway/server.ts > "$LOGS_DIR/memory-core.log" 2>&1 &
  write_pid memory-core 8420 $!
  echo "  memory-core pid $(cat "$RUN_DIR/memory-core.pid")"
}

start_knowledge() {
  echo "Starting knowledge (8424)..."
  cd "$REPO/MemoryKnowledge"
  nohup npm run dev > "$LOGS_DIR/knowledge.log" 2>&1 &
  write_pid knowledge 8424 $!
  echo "  knowledge pid $(cat "$RUN_DIR/knowledge.pid")"
}

start_proxy() {
  echo "Starting proxy (8096)..."
  cd "$REPO/MemoryProxy"
  # Proxy upstream is env-overridable so this stays provider-agnostic.
  # Copy run/proxy.config.yaml.example to run/proxy.config.yaml and edit,
  # or set PROXY_CONFIG to point at your own config.
  local proxy_cfg="${PROXY_CONFIG:-$RUN_DIR/proxy.config.yaml}"
  nohup npm run start:config -- --config "$proxy_cfg" > "$LOGS_DIR/proxy.log" 2>&1 &
  write_pid proxy 8096 $!
  echo "  proxy pid $(cat "$RUN_DIR/proxy.pid")"
}

start_one() {
  case "$1" in
    memory-core) start_memory_core ;;
    knowledge)   start_knowledge ;;
    proxy)       start_proxy ;;
    *) echo "unknown service: $1 (expected: memory-core | knowledge | proxy)" >&2; exit 2 ;;
  esac
}

stop_one() {
  local svc="$1"
  if [[ -f "$RUN_DIR/$svc.pid" ]]; then
    local pid; pid="$(cat "$RUN_DIR/$svc.pid")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null && echo "stopped $svc (pid $pid)"
    else
      echo "$svc not running (stale pid $pid)"
    fi
    rm -f "$RUN_DIR/$svc.pid"
  else
    echo "$svc: no pid file"
  fi
}

show_status() {
  printf "%-14s %-6s %-8s %s\n" SERVICE PORT PID STATUS
  for svc in "${ALL_SERVICES[@]}"; do
    local port; port="$(port_for "$svc")"
    local pid="-"
    if [[ -f "$RUN_DIR/$svc.pid" ]]; then pid="$(cat "$RUN_DIR/$svc.pid")"; fi
    local code; code="$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/health" 2>/dev/null || true)"
    local status
    if [[ "$code" == "200" ]]; then status="healthy (HTTP $code)"
    elif [[ "$code" != "000" && -n "$code" ]]; then status="up (HTTP $code)"
    else status="down"; fi
    # cross-check pid liveness
    if [[ "$pid" != "-" ]] && ! kill -0 "$pid" 2>/dev/null; then status="$status (pid $pid dead)"; fi
    printf "%-14s %-6s %-8s %s\n" "$svc" "$port" "$pid" "$status"
  done
}

# ── arg parsing ──
mode="start"
services=()
for arg in "$@"; do
  case "$arg" in
    --stop)    mode="stop" ;;
    --status)  mode="status" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*)       echo "unknown flag: $arg" >&2; exit 2 ;;
    *)         services+=("$arg") ;;
  esac
done
[[ ${#services[@]} -eq 0 ]] && services=("${ALL_SERVICES[@]}")

case "$mode" in
  status) show_status ;;
  stop)   for s in "${services[@]}"; do stop_one "$s"; done ;;
  start)
    # guard against starting memory-core when something already holds 8420
    for s in "${services[@]}"; do
      if [[ "$s" == "memory-core" ]]; then
        if ss -tlnH 2>/dev/null | grep -qE ':8420\b'; then
          echo "ERROR: port 8420 already in use — memory-core may already be running." >&2
          echo "       Run './run/start-local.sh --status' to check, or start only: knowledge proxy" >&2
          exit 1
        fi
      fi
    done
    for s in "${services[@]}"; do start_one "$s"; done
    echo ""
    echo "Launching. Logs in $LOGS_DIR"
    echo "  memory-core: http://localhost:8420/health"
    echo "  knowledge:   http://localhost:8424/health"
    echo "  proxy:       http://localhost:8096/health"
    echo "  panel UI:    not started (requires MemoryPanel build)"
    ;;
esac
