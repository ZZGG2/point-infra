#!/usr/bin/env bash
# 공통 AI 규칙(team/ai/AGENTS.common.md)을 각 레포 AGENTS.md 의 COMMON 블록에 덮어쓴다.
# 레포별 규칙(블록 바깥)은 보존된다.
# usage: ./scripts/sync-ai-rules.sh [repo_dir ...]   (기본: 자신 + ../point-backend ../point-frontend)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/team/ai/AGENTS.common.md"
TARGETS=("$@")
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=("$ROOT" "$ROOT/../point-backend" "$ROOT/../point-frontend")

for repo in "${TARGETS[@]}"; do
  f="$repo/AGENTS.md"
  [[ -f "$f" ]] || { echo "skip: $f 없음"; continue; }
  python3 - "$SRC" "$f" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
common = open(src, encoding="utf-8").read().strip()
body = open(dst, encoding="utf-8").read()
pat = re.compile(r"<!-- =+ COMMON RULES START.*?COMMON RULES END[^>]*-->", re.S)
if not pat.search(body):
    sys.exit(f"COMMON 블록 마커 없음: {dst}")
open(dst, "w", encoding="utf-8").write(pat.sub(lambda _: common, body, count=1))
print(f"synced: {dst}")
PY
done
