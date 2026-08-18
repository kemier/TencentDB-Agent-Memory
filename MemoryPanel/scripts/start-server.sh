#!/usr/bin/env bash
# start-server.sh — start the Team Memory Control Panel (MemoryPanel) detached.
#
# Usage:
#   bash start-server.sh [port]
#   PORT  default 8123
#
# Idempotent: exits 0 immediately if the panel is already healthy on the port.
# Launches with setsid + nohup so the process survives the calling shell/session.
# Uses the same FTS5-capable node pinned for the knowledge stack (v22.23.2).
# Runs via tsx (src/index.ts) — the panel ships no prebuilt dist/.
#
# NOTE on binding: zsh exports HOST=<hostname> as a built-in shell variable, and
# dotenv (loadDotenv) does NOT override already-set env vars — so loadPanelConfig
# picks HOST=seroiuts00847 over the .env HOST=127.0.0.1 and binds the LAN IP.
# We therefore export HOST explicitly before launch (PANEL_HOST overrides).
# Health probing uses a hostname fallback to detect an already-running instance.
#
# Requires: MemoryPanel repo with node_modules installed (tsx + @hono/node-server)
#           and web/dist built (the UI is served same-origin by the panel).

set -euo pipefail

PORT="${1:-8123}"
REPO="${PANEL_REPO:-/workspace/git/ezennin/TencentDB-Agent-Memory/MemoryPanel}"
NODE_HOME="${PANEL_NODE_HOME:-${HOME}/.local/lib/node-v22.23.2}"
LOG_FILE="/tmp/panel-server-${PORT}.log"
RUN_DIR="${RUN_DIR:-$(dirname "$REPO")/run}"
PID_FILE="${RUN_DIR}/panel.pid"

if [[ ! -x "${NODE_HOME}/bin/node" ]]; then
  echo "error: pinned node not found at ${NODE_HOME}/bin/node (set PANEL_NODE_HOME)" >&2
  exit 1
fi
if [[ ! -d "${REPO}/node_modules/.bin" ]]; then
  echo "error: ${REPO}/node_modules missing — run pnpm install (backend) + cd web && npm install (frontend)" >&2
  exit 1
fi
if [[ ! -x "${REPO}/node_modules/.bin/tsx" ]]; then
  echo "error: tsx not found in ${REPO} — expected dev dependency" >&2
  exit 1
fi
if [[ ! -f "${REPO}/web/dist/index.html" ]]; then
  echo "error: frontend not built — cd ${REPO}/web && npm run build (produces web/dist)" >&2
  exit 1
fi

# ── health probe helper: returns 0 if any candidate answers 200 ──
probe() {
  local h; for h in "127.0.0.1" "localhost" "$(hostname 2>/dev/null)"; do
    if [[ -n "$h" ]] && curl -sf -m 1 "http://${h}:${PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Already up? Nothing to do (idempotent).
if probe; then
  # Refresh pid file if a panel is actually listening (catches restarts).
  live=$(ss -tlnp 2>/dev/null | grep "[:.]${PORT}\b" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
  if [[ -n "$live" ]]; then
    mkdir -p "$RUN_DIR" 2>/dev/null || true
    echo "$live" > "$PID_FILE"
  fi
  echo "panel ${PORT} already healthy — nothing to do"
  exit 0
fi

export PATH="${NODE_HOME}/bin:${PATH}"
unset NPM_CONFIG_PREFIX

echo "Starting MemoryPanel on port ${PORT}"
echo "  repo: ${REPO}"
echo "  log:  ${LOG_FILE}"

cd "${REPO}"
setsid nohup env \
  PORT="$PORT" \
  HOST="${PANEL_HOST:-127.0.0.1}" \
  node_modules/.bin/tsx src/index.ts > "${LOG_FILE}" 2>&1 < /dev/null &
disown

# Persist the launcher pid (the setsid/nohup child) for status/restart tools.
LAUNCHER_PID=$!
mkdir -p "$RUN_DIR" 2>/dev/null || true
echo "$LAUNCHER_PID" > "$PID_FILE"

# Wait for health (up to 20s — panel also runs a startup LLM-binding sync).
for i in $(seq 1 20); do
  if probe; then
    echo "OK — healthy on http://127.0.0.1:${PORT}"
    # Refresh with the actual listener pid if it differs from the launcher pid.
    live=$(ss -tlnp 2>/dev/null | grep "[:.]${PORT}\b" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    if [[ -n "$live" ]]; then
      echo "$live" > "$PID_FILE"
    fi
    exit 0
  fi
  sleep 1
done

echo "error: panel did not become healthy within 20s — check ${LOG_FILE}" >&2
echo "----- tail of log -----" >&2
tail -20 "${LOG_FILE}" >&2 || true
exit 1
