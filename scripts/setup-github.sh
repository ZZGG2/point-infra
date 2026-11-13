#!/usr/bin/env bash
# 레포 초기 설정: 라벨 동기화 + main 브랜치 보호 + 머지 방식 (gh CLI, 레포 admin 권한 필요)
# usage: ./scripts/setup-github.sh <owner>/<repo> "<필수 status check 이름>,..."
#   예: ./scripts/setup-github.sh my-org/point-backend "test,lint"
set -euo pipefail
REPO="${1:?owner/repo}"
CHECKS="${2:-}"
LABELS="$(dirname "$0")/../.github/labels.yml"

echo "▶ 라벨 동기화"
python3 - "$LABELS" <<'PY' | while IFS=$'\t' read -r name color desc; do
import sys, yaml
for l in yaml.safe_load(open(sys.argv[1])):
    print(f"{l['name']}\t{l['color']}\t{l.get('description','')}")
PY
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
  echo "  - $name"
done

echo "▶ 머지 방식: Squash only, 머지 후 브랜치 자동 삭제"
gh api -X PATCH "repos/$REPO" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE >/dev/null

echo "▶ main 브랜치 보호"
CONTEXTS=$(python3 -c "import json,sys;print(json.dumps([c for c in sys.argv[1].split(',') if c]+['pr-title']))" "$CHECKS")
gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": $CONTEXTS },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
echo "✅ 완료: $REPO  (PR 제목 검사 job 'pr-title' 은 기본 포함)"
