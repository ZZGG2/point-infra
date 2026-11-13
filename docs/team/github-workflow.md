# 팀 GitHub 운영 규칙

> 적용 대상: `point-infra`, `point-backend`, `point-frontend` 전체.
> 원칙: **이슈 없이 코드 없다 · main은 항상 배포 가능 · 작게 자주 머지.**

## 1. 레포지토리와 소유권

| 레포 | 주 담당 | 필수 리뷰어 (CODEOWNERS) | 배포 |
|---|---|---|---|
| `point-infra` | 인프라 담당 | 인프라 담당 1명 + (DR/네트워크 변경 시) 2명 | Terraform apply, ArgoCD |
| `point-backend` | 백엔드 담당 | 백엔드 1명 (`api/`, `db/migration` 변경 시 + 인프라 1명) | 이미지 → infra 태그 PR |
| `point-frontend` | 프론트 담당 | 프론트 1명 | web 이미지 (ECR + Artifact Registry) |

- 팀원 GitHub ID와 역할은 각 레포 `.github/CODEOWNERS`에 등록한다.
- 설계 문서·ADR·팀 규칙의 **원본은 point-infra**에만 둔다. 다른 레포는 링크로 참조.

## 2. 작업 흐름 (Issue → Branch → PR → Merge)

```
① 이슈 생성 (템플릿) ─▶ ② 담당자 지정 + 라벨 + 보드 "Todo"
       │
③ 브랜치 생성  feat/#42-quiz-lua
       │
④ 작업 + 커밋 (Conventional Commits)  ── 매일 main rebase
       │
⑤ Draft PR (일찍 열기) ─▶ CI 통과 ─▶ Ready for review
       │
⑥ 리뷰 (24시간 내 1차 응답) ─▶ 수정 ─▶ 승인
       │
⑦ Squash Merge (PR 작성자가 직접) ─▶ 브랜치 자동 삭제 ─▶ 이슈 자동 Close
```

### 이슈 규칙
- 모든 작업은 이슈부터. 템플릿: `feature`, `bug`, `infra`, `adr`, `task`
- 이슈 1개 = PR 1개가 원칙, **최대 2~3일 분량**. 크면 하위 이슈로 쪼갠다.
- 착수 = 본인을 Assignee로 지정 + 보드 `In Progress`로 이동. **Assignee가 있는 이슈의 파일 영역은 다른 사람이 건드리지 않는다.**

### GitHub Projects 보드
`Backlog → Todo(이번 주) → In Progress → In Review → Done`
- 필드: `Repo`, `Phase`(0~6), `Estimate`(S/M/L), `Iteration`(주 단위)
- 주 1회 스프린트 회의에서 Backlog → Todo 선정

## 3. 브랜치 전략 — GitHub Flow

| 브랜치 | 용도 | 규칙 |
|---|---|---|
| `main` | 항상 배포 가능 | 직접 push 금지, PR만 |
| `<type>/#<이슈>-<설명>` | 작업 | 수명 3일 이내 권장, 머지 후 자동 삭제 |

- type: `feat` `fix` `infra` `docs` `test` `refactor` `chore` `ci` `hotfix`
- 설명은 영어 소문자 kebab-case: `feat/#42-quiz-lua`, `infra/#57-gcp-ha-vpn`
- `develop` / `release` 브랜치는 두지 않는다 (소규모 팀 + GitOps에서 불필요한 병합 충돌만 증가).

## 4. 커밋 규칙

```
<type>(<scope>): <요약 — 50자 이내, 명령형>

<본문 — 무엇을/왜 (선택)>

Refs: #42
```
| scope 예시 | backend: `user` `point` `event` `common` `api` · frontend: `auth` `point` `event` `ui` · infra: `vpc` `eks` `rds` `cdc` `dr` `k8s` `docs` |
|---|---|

- 하나의 커밋 = 하나의 논리 변경. "WIP", "수정", "asdf" 금지 (Squash 전 정리 대상이라도 리뷰 가독성을 위해).
- PR 제목도 같은 형식 → **Squash 시 PR 제목이 main의 커밋 메시지가 된다.**

## 5. Pull Request 규칙

| 항목 | 규칙 |
|---|---|
| 크기 | 변경 400줄 이내 권장 (생성 파일, lock 제외). 초과 시 사유 기재 |
| 템플릿 | 필수 (`.github/pull_request_template.md`) — 목적, 변경점, 테스트, AI 사용, 체크리스트 |
| 연결 | 본문에 `Closes #이슈번호` |
| Draft | 작업 시작 직후 Draft로 열어 방향을 공유 (충돌 조기 발견) |
| 승인 | 일반 1명, **infra의 `envs/`·`network`·DR 관련 2명** |
| 머지 방식 | **Squash merge만 허용** (merge commit, rebase merge 비활성화) |
| 머지 주체 | 승인 후 **PR 작성자**가 머지 |
| CI | 모든 필수 체크 통과 + 대화(conversation) 전부 Resolve |

### 리뷰 규칙
- 1차 응답 **24시간 이내** (주말 제외). 어려우면 "내일 볼게요"라도 남긴다.
- 코멘트 접두어로 강도를 명확히:
  | 접두어 | 의미 | 머지 전 해결 |
  |---|---|---|
  | `[must]` | 버그, 보안, 규칙 위반 | 필수 |
  | `[should]` | 설계·가독성 개선 | 원칙적으로 해결, 합의 시 후속 이슈 |
  | `[nit]` | 사소한 취향 | 선택 |
  | `[q]` | 질문 | 답변 필수 |
- 리뷰는 코드에 대해, 사람에 대해 하지 않는다. 승인 시 무엇을 확인했는지 한 줄 남긴다.
- **AI 생성 코드도 동일 기준.** 작성자가 설명하지 못하면 `[must]`.

## 6. 브랜치 보호 (Rulesets) — 모든 레포 `main`

| 설정 | 값 |
|---|---|
| Require pull request | ✅ 승인 1 (infra 2: CODEOWNERS로 경로별) |
| Require review from Code Owners | ✅ |
| Dismiss stale approvals on new commits | ✅ |
| Require status checks | ✅ 각 레포 CI job + `pr-title` |
| Require branches to be up to date | ✅ |
| Require conversation resolution | ✅ |
| Require linear history | ✅ |
| Block force pushes / deletions | ✅ |
| Allowed merge methods | Squash only |
| Automatically delete head branches | ✅ (레포 설정) |

자동 적용: `scripts/setup-github.sh <owner>/<repo>` (라벨 + 브랜치 보호)

## 7. 라벨

| 그룹 | 라벨 |
|---|---|
| 유형 | `type:feature` `type:bug` `type:infra` `type:docs` `type:adr` `type:chore` |
| 우선순위 | `P0` `P1` `P2` |
| 영역 | `area:user` `area:asset` `area:point` `area:event` `area:cs` `area:network` `area:dr` `area:cicd` |
| 환경 선점 (infra) | `env:aws-main` `env:gcp-dr-standby` `env:gcp-dr-compute` |
| 상태 | `blocked` `needs-discussion` `breaking-change` `cross-repo` |
| 기타 | `good-first-issue` `ai-assisted` |

정의 파일: `.github/labels.yml`

## 8. 교차 레포 변경 규칙 (API·스키마·인프라 연동)

레포가 나뉘어 있으므로 **"계약을 먼저, 구현은 나중에"** 순서를 지킨다.

| 변경 | 순서 |
|---|---|
| API 추가 (하위 호환) | ① backend PR: `openapi.yaml` + 구현 → 머지 ② frontend: `gen:api` 후 사용 |
| API Breaking Change | ① backend에 `breaking-change` + `cross-repo` 이슈, frontend 연계 이슈 링크 ② 새 필드/버전 추가(구 필드 유지) ③ frontend 전환 ④ 구 필드 제거 PR (**Expand → Migrate → Contract**) |
| 새 환경 변수 / 시크릿 | ① infra PR: ConfigMap·ExternalSecret 추가 → 머지 ② backend PR: 사용 코드 |
| 새 Kafka 토픽 | ① infra: data-architecture 문서 + 토픽 정의 ② backend: producer/consumer |
| DB 테이블 추가 (CDC 대상) | ① backend: Flyway ② infra: `cdc/` publication·connector 갱신 (같은 주 내) |
| 공통 AI 규칙 변경 | ① infra: `team/ai/AGENTS.common.md` 수정 + 버전 업 ② `make sync-ai-rules` ③ 각 레포 동기화 PR |

- 교차 레포 PR은 본문에 `Related: <org>/<repo>#<번호>`로 상호 링크.

## 9. 충돌 예방 수칙

1. **매일 작업 시작 시** `git fetch && git rebase origin/main`.
2. 같은 파일을 2명 이상 수정할 예정이면 이슈 코멘트로 먼저 조율 (특히 `build.gradle`, `package.json`, `overlays/*/kustomization.yaml`, `docs/02-adr/README.md`).
3. Terraform 환경은 `env:*` 라벨로 **선점**한 사람만 수정. State 락 에러 발생 시 강제 해제 금지 → 팀 채널에 공유.
4. 포맷터 일괄 실행, 대규모 이름 변경은 **공지 후 단독 PR**로, 다른 PR이 적은 시간에 머지.
5. AI에게 작업시킬 때 **범위(파일/디렉터리)를 명시**한다 → [ai-collaboration.md](ai-collaboration.md)
6. 충돌 해결 시 상대 코드를 지웠다면 PR에 명시하고 해당 작성자를 리뷰어로 추가.

## 10. 버전 관리 & 릴리스

| 레포 | 버전 | 태그 | 산출물 |
|---|---|---|---|
| backend | SemVer `v0.x.y` | main 머지 시 이미지 태그 = `sha-<7자리>`, 릴리스 시 `v0.3.0` | ECR / Artifact Registry 이미지 |
| frontend | SemVer | 동일 | web 컨테이너 이미지 태그 (Git SHA) — ECR / Artifact Registry |
| infra | 태그 없음 (main = 현재 상태) | DR 훈련 시점 태그 `drill-YYYYMMDD` | - |

- 릴리스 노트: GitHub Releases 자동 생성 (Squash 커밋 제목 기준) — Conventional Commits가 중요한 이유.

## 11. 시크릿 & 보안

- 시크릿은 **GitHub Environments**(`dev`, `prod`, `dr-production`)의 Secrets/Variables에만. 레포 파일 금지.
- 클라우드 인증은 OIDC만 (Access Key 발급 금지).
- 커밋 전 `gitleaks` (pre-commit 훅). 유출 시: 즉시 키 폐기 → 팀 공유 → 히스토리 정리는 그 다음.
- Dependabot: 보안 업데이트만 자동 PR, 버전 업데이트는 월 1회 담당자가 묶어서.

## 12. 커뮤니케이션

| 상황 | 채널 |
|---|---|
| 작업 논의, 결정 기록 | GitHub 이슈/PR 코멘트 (메신저 결정은 이슈에 요약 남기기) |
| 빠른 질문, 장애 공유 | 팀 메신저 |
| 설계 변경 | ADR 이슈 → 회의 → ADR PR |
| 주간 | 스프린트 회의 (보드 리뷰, 다음 주 Todo 선정) |
