#!/usr/bin/env python3
"""Filter a /proc/<pid>/environ dump down to gateway-relevant env vars.

Usage: filter-gateway-env.py <env-dump> > <export-script>

Keeps only TDAI_*/STATE_BACKEND/COS_/REDIS_/LANGFUSE_/KAFKA_METRIC_/OTEL_/
SHARK_/SCANNER_/CLICKHOUSE_/KNOWLEDGE_/TENCENTDB_/MEMORY_* — the noisy
shell/VS Code vars (GUESTFISH_PS1, BASH_FUNC_*, VSCODE_NLS_CONFIG, ...) are
dropped because they break naive shell sourcing.
"""

import re
import sys


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gateway-env.txt"
    raw = open(src, "rb").read().decode("utf-8", "replace")
    keep = re.compile(
        r"^(TDAI_|STATE_BACKEND|COS_|REDIS_|LANGFUSE_|KAFKA_METRIC_|OTEL_"
        r"|SHARK_|SCANNER_|CLICKHOUSE_|KNOWLEDGE_|TENCENTDB_|MEMORY_)"
    )
    for line in raw.splitlines():
        if "=" in line and keep.match(line):
            k, _, v = line.partition("=")
            print(f"export {k}={v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
