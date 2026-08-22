#!/usr/bin/env bash
# Install Mac launchd agents for the native memory stack.
#
#   bash scripts/install-mac-launchd.sh          # install + bootstrap
#   bash scripts/install-mac-launchd.sh uninstall
#
# Installs:
#   com.local.tdai-gateway  — KeepAlive MemoryCore gateway (:8420)
#   com.local.tdai-memory   — RunAtLoad: scripts/start-all.sh start (panel + kickstart gateway)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"

render() {
  local src="$1" dst="$2"
  sed -e "s|@REPO@|$ROOT|g" -e "s|@HOME@|$HOME|g" "$src" >"$dst"
}

install_one() {
  local label="$1" template="$2"
  local dst="$DEST/$label.plist"
  render "$template" "$dst"
  launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$dst"
  ok "Installed $label"
}

uninstall_one() {
  local label="$1"
  launchctl bootout "$DOMAIN/$label" 2>/dev/null && ok "Removed $label" || warn "Not loaded: $label"
  rm -f "$DEST/$label.plist"
}

ok()  { printf '  OK  %s\n' "$*"; }
warn(){ printf '  WARN %s\n' "$*"; }

mkdir -p "$DEST"
chmod +x "$ROOT/scripts/start-all.sh"

case "${1:-install}" in
  install)
    install_one "com.local.tdai-gateway" "$ROOT/deploy/mac/com.local.tdai-gateway.plist"
    install_one "com.local.tdai-memory" "$ROOT/deploy/mac/com.local.tdai-memory.plist"
    bash "$ROOT/scripts/start-all.sh" restart
    ;;
  uninstall)
    uninstall_one "com.local.tdai-memory"
    uninstall_one "com.local.tdai-gateway"
    bash "$ROOT/scripts/start-all.sh" stop || true
    ;;
  *)
    echo "usage: $0 [install|uninstall]" >&2
    exit 2
    ;;
esac
