#!/usr/bin/env bash
# All-in-one native memory stack on Mac: Ollama -> Gateway (8420) -> MemoryPanel (8125).
#
#   bash scripts/start-all.sh              # start missing services, print status
#   bash scripts/start-all.sh stop         # stop panel + gateway (ollama unchanged)
#   bash scripts/start-all.sh restart      # stop then start (use after git pull / build)
#   bash scripts/start-all.sh restart-panel  # force-restart panel only (picks up new code)
#   bash scripts/start-all.sh status       # health only
#
# Launchd (login):
#   bash scripts/install-mac-launchd.sh    # installs com.local.tdai-memory + gateway plists
#
# Services:
#   Ollama        :11434  (brew services / homebrew launchd)
#   tdai-gateway  :8420   (com.local.tdai-gateway KeepAlive launchd when installed)
#   MemoryPanel   :8125   (nohup; log /tmp/memory-panel.log)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/MemoryCore"
PANEL="$ROOT/MemoryPanel"
CONFIG="$CORE/tdai-gateway.mac.yaml"
PANEL_LOG="/tmp/memory-panel.log"
PANEL_PIDFILE="/tmp/memory-panel.pid"
GATEWAY_PIDFILE="/tmp/memory-core.pid"
GATEWAY_LOG="/tmp/memory-core.log"
LAUNCHD_GATEWAY_LABEL="com.local.tdai-gateway"
LAUNCHD_MEMORY_LABEL="com.local.tdai-memory"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8420}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
PANEL_URL="${PANEL_URL:-http://127.0.0.1:8125}"

# launchd PATH is minimal; prefer Homebrew node, then nvm default.
if [[ -x /opt/homebrew/bin/node ]]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
elif [[ -x /usr/local/bin/node ]]; then
  export PATH="/usr/local/bin:/usr/local/sbin:${PATH:-}"
fi
if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
fi

log()  { printf '[start-all] %s\n' "$*"; }
ok()   { printf '  OK  %s\n' "$*"; }
warn() { printf '  WARN %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*" >&2; }

healthy() { curl -sf -m 2 "$1" >/dev/null 2>&1; }

start_ollama() {
  if healthy "$OLLAMA_URL/api/tags"; then
    ok "Ollama running at $OLLAMA_URL"
    return
  fi
  log "Starting Ollama (brew services)..."
  if command -v brew >/dev/null 2>&1; then
    brew services start ollama >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do healthy "$OLLAMA_URL/api/tags" && break; sleep 1; done
  fi
  if healthy "$OLLAMA_URL/api/tags"; then
    ok "Ollama running at $OLLAMA_URL"
  else
    warn "Ollama not reachable — embeddings may fail (brew services list | grep ollama)"
  fi
}

start_gateway() {
  if healthy "$GATEWAY_URL/health"; then
    ok "Gateway healthy at $GATEWAY_URL"
    return
  fi
  if launchctl list 2>/dev/null | grep -q "$LAUNCHD_GATEWAY_LABEL"; then
    log "Gateway down — kickstart $LAUNCHD_GATEWAY_LABEL ..."
    launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_GATEWAY_LABEL" || warn "kickstart failed"
  else
    log "Starting gateway via nohup (log=$GATEWAY_LOG)..."
    [[ -f "$CONFIG" ]] || { fail "Missing config: $CONFIG"; exit 1; }
    cd "$CORE"
    [[ -d node_modules ]] || npm install
    export TDAI_GATEWAY_CONFIG="$CONFIG"
    export TDAI_GATEWAY_API_KEY="${TDAI_GATEWAY_API_KEY:-local}"
    export TDAI_LLM_API_KEY="${TDAI_LLM_API_KEY:-local}"
    nohup node --import tsx src/gateway/server.ts >>"$GATEWAY_LOG" 2>&1 &
    echo $! >"$GATEWAY_PIDFILE"
    disown 2>/dev/null || true
  fi
  for _ in $(seq 1 30); do healthy "$GATEWAY_URL/health" && break; sleep 1; done
  if healthy "$GATEWAY_URL/health"; then
    ok "Gateway healthy at $GATEWAY_URL"
  else
    fail "Gateway failed health check — tail $GATEWAY_LOG"
    exit 1
  fi
}

ensure_panel_env() {
  local env_file="$PANEL/.env"
  if [[ ! -f "$env_file" ]]; then
    [[ -f "$PANEL/.env.example" ]] || { fail "Missing $PANEL/.env.example"; exit 1; }
    cp "$PANEL/.env.example" "$env_file"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      sed -i '' 's/^PORT=.*/PORT=8125/' "$env_file"
    else
      sed -i 's/^PORT=.*/PORT=8125/' "$env_file"
    fi
    log "Created $env_file with PORT=8125"
  fi
  if ! grep -q '^DEFAULT_GATEWAY_MEMORY_USER_ID=' "$env_file" 2>/dev/null; then
    echo 'DEFAULT_GATEWAY_MEMORY_USER_ID=zaedinzeng' >>"$env_file"
  fi
}

stop_panel() {
  local pid=""
  if [[ -f "$PANEL_PIDFILE" ]]; then
    pid="$(cat "$PANEL_PIDFILE" 2>/dev/null || true)"
  fi
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    ok "Stopped MemoryPanel (pid=$pid)"
  fi
  local port_pid
  port_pid="$(lsof -tiTCP:8125 -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${port_pid:-}" ]]; then
    kill "$port_pid" 2>/dev/null || true
    ok "Stopped listener on :8125 (pid=$port_pid)"
  fi
  rm -f "$PANEL_PIDFILE"
}

start_panel() {
  local force="${1:-0}"
  if [[ "$force" != "1" ]] && healthy "$PANEL_URL/"; then
    ok "MemoryPanel serving at $PANEL_URL"
    return
  fi
  if healthy "$PANEL_URL/"; then
    stop_panel
    sleep 1
  fi
  ensure_panel_env
  log "Starting MemoryPanel (log=$PANEL_LOG)..."
  cd "$PANEL"
  [[ -d node_modules ]] || npm install
  nohup node --import tsx src/index.ts >>"$PANEL_LOG" 2>&1 &
  echo $! >"$PANEL_PIDFILE"
  disown 2>/dev/null || true
  for _ in $(seq 1 20); do healthy "$PANEL_URL/" && break; sleep 1; done
  if healthy "$PANEL_URL/"; then
    ok "MemoryPanel serving at $PANEL_URL"
  else
    fail "MemoryPanel failed to start — tail $PANEL_LOG"
    exit 1
  fi
}

stop_gateway() {
  local mode="${1:-soft}"
  if launchctl list 2>/dev/null | grep -q "$LAUNCHD_GATEWAY_LABEL"; then
    if [[ "$mode" == "hard" ]]; then
      launchctl bootout "gui/$(id -u)/$LAUNCHD_GATEWAY_LABEL" 2>/dev/null && ok "Stopped launchd gateway" \
        || warn "Could not bootout $LAUNCHD_GATEWAY_LABEL"
    else
      launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_GATEWAY_LABEL" 2>/dev/null || true
      ok "Restarted gateway launchd ($LAUNCHD_GATEWAY_LABEL)"
    fi
  elif [[ -f "$GATEWAY_PIDFILE" ]]; then
    local pid
    pid="$(cat "$GATEWAY_PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      ok "Stopped gateway (pid=$pid)"
    fi
    rm -f "$GATEWAY_PIDFILE"
  fi
  if [[ "$mode" == "hard" ]]; then
    local port_pid
    port_pid="$(lsof -tiTCP:8420 -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${port_pid:-}" ]]; then
      kill "$port_pid" 2>/dev/null || true
      ok "Stopped listener on :8420 (pid=$port_pid)"
    fi
  fi
}

status_all() {
  echo "-- Memory stack status --"
  healthy "$OLLAMA_URL/api/tags" && ok "Ollama        $OLLAMA_URL" || warn "Ollama        DOWN"
  healthy "$GATEWAY_URL/health"  && ok "Gateway       $GATEWAY_URL" || warn "Gateway       DOWN"
  healthy "$PANEL_URL/"          && ok "MemoryPanel   $PANEL_URL" || warn "MemoryPanel   DOWN"
}

cmd="${1:-start}"
case "$cmd" in
  start|--start)
    start_ollama
    start_gateway
    start_panel 0
    echo
    status_all
    ;;
  stop|--stop)
    stop_panel
    stop_gateway hard
    ;;
  restart|--restart)
    stop_panel
    stop_gateway soft
    sleep 1
    start_ollama
    start_gateway
    start_panel 1
    echo
    status_all
    ;;
  restart-panel|--restart-panel)
    start_panel 1
    ;;
  status|--status)
    status_all
    ;;
  *)
    echo "usage: $0 [start|stop|restart|restart-panel|status]" >&2
    exit 2
    ;;
esac
