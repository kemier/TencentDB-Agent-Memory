#!/usr/bin/env bash
# Bootstrap metadata for vscode-acp Model B: team=default, agent=pi-agent (+ chat_memory asset).
set -euo pipefail

GATEWAY="${GATEWAY:-http://127.0.0.1:8420}"
API_KEY="${API_KEY:-local}"
SERVICE_ID="${SERVICE_ID:-default}"
TEAM_ID="${TEAM_ID:-default}"
AGENT_ID="${AGENT_ID:-pi-agent}"
AGENT_NAME="${AGENT_NAME:-PI Agent}"

echo "[bootstrap] gateway=${GATEWAY} team=${TEAM_ID} agent=${AGENT_ID}"

python3 <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

gateway = os.environ.get("GATEWAY", "http://127.0.0.1:8420")
api_key = os.environ.get("API_KEY", "local")
service_id = os.environ.get("SERVICE_ID", "default")
team_id = os.environ.get("TEAM_ID", "default")
agent_id = os.environ.get("AGENT_ID", "pi-agent")
agent_name = os.environ.get("AGENT_NAME", "PI Agent")


def post(path: str, body: dict, user_key: str | None = None) -> dict:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "x-tdai-service-id": service_id,
        "Content-Type": "application/json",
    }
    if user_key:
        headers["x-tdai-user-key"] = user_key
    req = urllib.request.Request(
        f"{gateway}{path}",
        data=json.dumps(body).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        payload = e.read().decode()
        try:
            return json.loads(payload)
        except json.JSONDecodeError:
            print(f"[bootstrap] HTTP {e.code} {path}: {payload}", file=sys.stderr)
            sys.exit(1)


# 1) Admin user
user_key = None
user_id = None
init = post("/v3/internal/meta/user/init-admin", {"username": "acp-admin"})
if init.get("code") == 0:
    user_key = init["data"]["user_key"]
    user_id = init["data"]["user_id"]
    print(f"[bootstrap] init-admin ok user_id={user_id}")
elif init.get("message", "").find("already_initialized") >= 0 or "already" in str(init.get("message", "")):
    admins = post("/v3/internal/meta/user/list-by-instance", {"page": 1, "page_size": 5, "user_type": "system_admin"})
    if admins.get("code") != 0 or not admins.get("data", {}).get("items"):
        print(f"[bootstrap] admin exists but list-by-instance failed: {admins}", file=sys.stderr)
        sys.exit(1)
    user_id = admins["data"]["items"][0]["user_id"]
    # Create a fresh API key for bootstrap (admin-only)
    key_resp = post(
        "/v3/meta/user-key/create",
        {"user_id": user_id, "name": "bootstrap"},
        user_key=None,
    )
    # user-key/create requires user key — use internal path unavailable. Fall back: re-init impossible.
    # Query sqlite for default key is out of scope; require saved key file or empty DB.
    key_file = os.path.expanduser("~/.memory-tencentdb/bootstrap-admin-key")
    if os.path.isfile(key_file):
        user_key = open(key_file).read().strip()
        print(f"[bootstrap] loaded admin key from {key_file}")
    else:
        print(
            "[bootstrap] ERROR: metadata already initialized but no ~/.memory-tencentdb/bootstrap-admin-key\n"
            "  Re-run on empty DB or save admin user_key from first init-admin to that file.",
            file=sys.stderr,
        )
        sys.exit(1)
else:
    print(f"[bootstrap] init-admin failed: {init}", file=sys.stderr)
    sys.exit(1)

if init.get("code") == 0:
    key_file = os.path.expanduser("~/.memory-tencentdb/bootstrap-admin-key")
    os.makedirs(os.path.dirname(key_file), exist_ok=True)
    with open(key_file, "w") as f:
        f.write(user_key)
    print(f"[bootstrap] saved admin key to {key_file}")

# 2) Team
team_get = post("/v3/meta/team/get", {"team_id": team_id}, user_key)
if team_get.get("code") == 0:
    print(f"[bootstrap] team {team_id} already exists")
else:
    team_create = post(
        "/v3/meta/team/create",
        {"team_id": team_id, "name": team_id, "owner_user_id": user_id},
        user_key,
    )
    if team_create.get("code") != 0:
        print(f"[bootstrap] team create failed: {team_create}", file=sys.stderr)
        sys.exit(1)
    print(f"[bootstrap] created team {team_id}")

# 3) Agent (+ chat_memory via MetadataService.createAgent)
agent_get = post("/v3/meta/agent/get", {"agent_id": agent_id}, user_key)
if agent_get.get("code") == 0:
    print(f"[bootstrap] agent {agent_id} already exists")
else:
    agent_create = post(
        "/v3/meta/agent/create",
        {
            "agent_id": agent_id,
            "team_id": team_id,
            "owner_user_id": user_id,
            "name": agent_name,
        },
        user_key,
    )
    if agent_create.get("code") != 0:
        print(f"[bootstrap] agent create failed: {agent_create}", file=sys.stderr)
        sys.exit(1)
    print(f"[bootstrap] created agent {agent_id} (chat_memory asset minted)")

print("[bootstrap] done")
PY
