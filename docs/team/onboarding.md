# 신규 팀원 온보딩

## Day 1 체크리스트
- [ ] GitHub Organization 초대 수락, 2FA 활성화
- [ ] 3개 레포 클론 — **같은 상위 폴더에** (`make sync-ai-rules`가 형제 경로를 사용)
  ```bash
  mkdir point-platform && cd point-platform
  git clone git@github.com:<org>/point-infra.git
  git clone git@github.com:<org>/point-backend.git
  git clone git@github.com:<org>/point-frontend.git
  ```
- [ ] `pre-commit install` (각 레포) — gitleaks, 포맷 검사
- [ ] 커밋 템플릿: `git config commit.template .gitmessage` (각 레포)
- [ ] 필독: 각 레포 `AGENTS.md` → [github-workflow.md](github-workflow.md) → [ai-collaboration.md](ai-collaboration.md) → [architecture-overview](../01-architecture/architecture-overview.md)
- [ ] 본인 AI 도구가 AGENTS.md를 읽는지 확인 (질문: "이 레포에서 금지된 작업 3가지는?")
- [ ] CODEOWNERS에 본인 ID 추가 PR (첫 PR 연습)

## 로컬 개발
| 레포 | 명령 |
|---|---|
| backend | `make local-up && make run-monolith` |
| frontend | `npm ci && npm run dev` (API: `VITE_API_BASE_URL=http://localhost:8080`) |
| infra | `terraform fmt`, `tflint` 만 로컬 실행. **apply는 CI만** |

## 클라우드 접근
- 콘솔: 읽기 전용 권한 (IAM Identity Center / GCP IAM Viewer). 변경은 Terraform PR.
- 비용 알림 채널 구독 필수.
