# Mac native memory stack (launchd)

Login-time stack orchestration for vscode-acp local development on macOS.

## Services

| Service | Port | launchd label |
|---------|------|----------------|
| MemoryCore Gateway | 8420 | `com.local.tdai-gateway` (KeepAlive) |
| MemoryPanel | 8125 | started by `com.local.tdai-memory` via `start-all.sh` |
| Ollama | 11434 | Homebrew `homebrew.mxcl.ollama` (optional) |

## Install

```bash
cd ~/projects/TencentDB-Agent-Memory
git pull kemier local/dev
cd MemoryPanel && npm install && npm run build
bash scripts/install-mac-launchd.sh
```

## Day-to-day

```bash
bash scripts/start-all.sh status
bash scripts/start-all.sh restart          # after git pull + build
bash scripts/start-all.sh restart-panel    # panel only
```

Logs: `/tmp/tdai-gateway.log`, `/tmp/memory-panel.log`, `/tmp/tdai-memory-start.log`

## Uninstall launchd

```bash
bash scripts/install-mac-launchd.sh uninstall
```
