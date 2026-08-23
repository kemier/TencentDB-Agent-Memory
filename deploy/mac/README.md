# Mac native memory stack (launchd)

Login-time stack orchestration for vscode-acp local development on macOS.

## Services

| Service | Port | launchd label |
|---------|------|----------------|
| MemoryCore Gateway | 8420 | `com.local.tdai-gateway` (KeepAlive) |
| MemoryPanel | 8125 | `com.local.tdai-panel` (KeepAlive, binds `0.0.0.0` for LAN access) |
| Stack bootstrap | — | `com.local.tdai-memory` runs `start-all.sh start` at login |
| Ollama | 11434 | Homebrew `homebrew.mxcl.ollama` (optional) |

### Ollama models (Mac)

| Ollama name | Source | Used for |
|---|---|---|
| `qwen3.8-4b-distill` | `empero-ai/Qwen3.8-4B-Distill-GGUF` (Q4_K_M via `HF_ENDPOINT=https://hf-mirror.com`) | L2/L3 memory summarization (`llm.model`) |
| `qwen2.5:1.5b-instruct` | Ollama library | L1 atom extraction (`memory.extraction.model`) |
| `bge-m3` | Ollama library | Embeddings |

Install / refresh the distill model:

```bash
HF_ENDPOINT=https://hf-mirror.com bash deploy/mac/install-qwen3.8-4b-distill-ollama.sh
```

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
