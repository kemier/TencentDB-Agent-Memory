# AGENTS.md

Guidance for AI agents working in this repository.

## Overview

TencentDB Agent Memory is a multi-service monorepo that gives AI agents
persistent, structured memory. The runtime stack is three Node.js/TypeScript
services:

| Service       | Port | Directory        | Role                                              |
|---------------|------|------------------|---------------------------------------------------|
| memory-core   | 8420 | `MemoryCore/`    | Memory gateway (L0-L3 pipeline, auth, metadata)   |
| knowledge     | 8424 | `MemoryKnowledge/` | Wiki + CodeGraph knowledge service              |
| proxy         | 8096 | `MemoryProxy/`   | LLM forwarding + memory/skill/knowledge injection |

Plus `MemoryPanel/` (web UI, not part of the core runtime) and `deploy/`
(Docker deployment scripts).

## Running the stack natively (no Docker)

The `deploy/global-images/*.sh` scripts assume Docker. This box runs **podman
5.6.0 with the CNI backend but no CNI plugins installed** (and no `netavark`,
no sudo), so `docker network create` fails. Run the services natively instead:

```bash
./run/start-local.sh         # start all 3 services (background, logs in run/logs/)
./run/start-local.sh --stop  # stop all 3
```

What `start-local.sh` launches:

```bash
# memory-core (8420)
cd MemoryCore
TDAI_GATEWAY_CONFIG=../run/tdai-gateway.yaml \
TDAI_GATEWAY_HOST=127.0.0.1 TDAI_GATEWAY_PORT=8420 \
TDAI_DATA_DIR=../run/data/memory-core \
TDAI_LLM_BASE_URL=http://127.0.0.1:8317/v1 \
TDAI_LLM_API_KEY=local TDAI_LLM_MODEL=gpt-oss-120b \
  node --import tsx src/gateway/server.ts

# knowledge (8424)
cd MemoryKnowledge && npm run dev        # tsx src/server.ts, reads .env

# proxy (8096)
cd MemoryProxy && npm run start:config -- --config ../run/proxy.config.yaml
```

### Preferred memory-core launch (used by the live setup)

The **currently running** memory-core instance is launched via the `nohup`
form below, which uses the **default data dir** (`~/.memory-tencentdb/memory-tdai/`)
and picks up `MemoryCore/tdai-gateway.yaml` from CWD (which enables bge-m3
embeddings via the EricAI proxy). This is the setup the `vscode-acp` memory
integration uses — do NOT switch it to the `run/` data dir.

```bash
cd MemoryCore
# Override LLM to the local EricAI proxy (the yaml's lkeap/deepseek-v3.2
# needs a Tencent API key we don't have; proxy serves gpt-oss-120b).
TDAI_LLM_BASE_URL="http://127.0.0.1:8317/v1" \
TDAI_LLM_API_KEY="local" \
TDAI_LLM_MODEL="gpt-oss-120b" \
  nohup node --import tsx src/gateway/server.ts \
    >> ~/.memory-tencentdb/memory-tdai/gateway-restart.log 2>&1 &
```

Notes:
- `nohup … &` may appear to hang the terminal (background job keeps the pipe
  open) but returns exit 0 immediately — verify via the log file
  (`gateway-restart.log`) and `/health`, not an interactive prompt.
- If port 8420 is already bound (`EADDRINUSE`), memory-core is already running
  — do not kill the running instance (it may belong to the user's active
  session); the new process simply fails to bind.
- Config resolution: `MemoryCore/tdai-gateway.yaml` is picked up from CWD.
  It points `data.baseDir` at `~/.memory-tencentdb/memory-tdai` and enables
  `memory.embedding` (bge-m3/heavy, 1024-dim) via the EricAI proxy.

### LLM upstream

All three services point at the local EricAI proxy `http://127.0.0.1:8317/v1`
(model `gpt-oss-120b`, apiKey `local` — auth disabled on the EricAI proxy).
`glm-5.2` is slow on first request; `gpt-oss-120b` responds fast.

**Primary model: `gpt-oss-120b`** (cheap, tagged `fast`, verified working for
the gateway's L1/L2/L3 extraction + skill extraction).

**Fallback (manual, no auto-failover):** the `StandaloneLLMRunner` has **no
automatic fallback** — it makes a single attempt and re-throws on failure.
If the primary model dies, the LLM-dependent pipelines (L1/L2/L3 extraction,
skill extraction) error out and `pipelineWorker.tasksFailed` increments in
`/health`. To switch, restart the gateway with `TDAI_LLM_MODEL=<model>`.

Verified cheap fallback candidates (via real requests to the EricAI proxy):
- `deepseek-v4-flash` — **best fallback**: returns real `content`, fast (~3s),
  tagged `fast`. Has a known prompt-echo quirk on low-context sessions.
- `gpt-oss-120b` — current primary; returns empty `content` on direct curl
  (thinking-mode model) but works through the gateway's runner.
- `Qwen3-Coder` — responds but empty `content`; not reliable.
- `Qwen3.6-27B` / `Qwen3.6-35B-A3B` — time out on cold start (>85s); too slow.

Note: `deepseek-v3.2` (in `MemoryCore/tdai-gateway.yaml` `llm.model`) is **not
served** by the EricAI proxy (only `deepseek-v4-pro` / `deepseek-v4-flash`).
The running gateway correctly overrides it via `TDAI_LLM_MODEL=gpt-oss-120b`.

### Cross-agent memory sharing (isolation model)

Memory is namespaced by `team_id` + `user_id` + `agent_id` (plus `service_id`).
The gateway receives isolation params from the ACP client; the live local setup
uses:

- `team_id=default`, `user_id=ezennin`, `service_id=default`
- `agent_id` varies by agent: `claude` / `codex` (each agent gets its own
  L1/L2/L3 namespace by default)
- `auth=disabled` — any Bearer token is accepted (loopback only)

**Cross-agent memory sharing** — two proposed options (not yet decided):

- **Option A (zero-code)**: configure `acp.memory.agentIdMap` to map all agents
  to the same `agent_id` (e.g. `ezennin`). Unifies all L1/L2/L3 namespaces, but
  loses per-agent persona distinction.
- **Option B (code change)**: make L1 recall cross-agent — filter by
  `team_id` + `user_id` only, dropping the `agent_id` filter. Keeps L2/L3
  isolated per agent, but is a code change to the recall path.

### Dependencies

`tsx` is a **devDependency** in `MemoryCore/`, `MemoryKnowledge/`, and
`MemoryProxy/`. A plain `npm install` skips it and you get
`tsx: command not found`. Install dev deps explicitly:

```bash
cd MemoryKnowledge && npm install --include=dev --no-audit --no-fund
cd MemoryProxy     && npm install --include=dev --no-audit --no-fund
```

### Key config files (generated, local-only)

- `run/tdai-gateway.yaml` — memory-core gateway config (start-local.sh)
- `MemoryCore/tdai-gateway.yaml` — memory-core gateway config (preferred/live)
- `run/proxy.config.yaml` — proxy config (upstream, tdai, auth, injection)
- `MemoryKnowledge/.env` — knowledge service config (`LLM_MODE=custom`)
- `run/.admin-key` — admin user_key (`sk-mem-...`) created via init-admin

## Important behaviors / gotchas

- **Proxy path format**: the proxy requires the spaceId in the URL path, e.g.
  `http://127.0.0.1:8096/claude-code/default/v1/chat/completions`, plus
  `Authorization: Bearer <user_key>`. A bare `/v1/chat/completions` returns
  `Authentication failed: missing service_id`.
- **Admin user**: create via
  `POST /v3/internal/meta/user/init-admin` with JSON body
  `{"username":"admin","user_key":"sk-mem-..."}` and header
  `x-tdai-service-id: default`. Use Python `urllib`/`json` to send the body —
  shell `curl -d` quoting produces `Invalid JSON body` (500).
  Validate with `POST /v3/meta/auth/verify` (returns `valid:true`).
- **Proxy startup WARN** `auth: FAIL: fetch failed` is a transient race — the
  proxy checks connectivity before memory-core finishes initializing. It
  resolves on its own; the proxy still serves requests.
- **memory-core FTS5 warning** (`no such module: fts5`) is non-fatal — BM25
  falls back to in-memory scoring.
- **MemoryPanel** is NOT part of the runtime start; it requires a frontend
  build and is optional.

## Git

- Branch `feat/local-memory-deploy` holds the native-run work.
- `run/`, `MemoryKnowledge/data/`, and `MemoryKnowledge/.env` are local/generated
  and untracked — do not commit credentials or data dirs.