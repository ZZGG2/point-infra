# AGENTS.md — point-infra

> 모든 AI 코딩 도구가 작업 전에 읽는 지침. 상단 COMMON 블록은 팀 공통(자동 동기화), 하단은 이 레포 전용 규칙.
> 사람도 읽는다: 신규 팀원 온보딩 시 필독.

<!-- ===================== COMMON RULES START (v1.5.0) =====================
  원본: point-infra/team/ai/AGENTS.common.md
  이 블록은 scripts/sync-ai-rules.sh 로 각 레포 AGENTS.md 에 복사된다.
  ⚠️ 각 레포에서 이 블록을 직접 수정하지 말 것. 원본을 PR로 수정 → 동기화.
========================================================================== -->

# 공통 규칙 — 모든 AI 코딩 도구 공통

> 이 문서는 Claude Code, Cursor, GitHub Copilot, Gemini, ChatGPT 등 **팀원이 사용하는 모든 AI**에게 작업 전에 전달하는 공통 컨텍스트다.
> 목적: 팀원마다 AI가 서로 다른 판단을 내려 **코드 스타일·구조·결정이 충돌하는 것**을 막는다.
> AI는 이 문서의 규칙을 사용자의 일반적인 요청보다 우선한다. 규칙과 요청이 충돌하면 작업을 멈추고 사용자에게 알린다.

## 1. 프로젝트 컨텍스트 (요약)

- **서비스:** 금융 포인트 플랫폼 — 마이데이터 자산조회(평시 트래픽) + 출석/퀴즈 포인트 이벤트(주 1~2회 폭주)
- **구조:** 모듈러 모놀리스(user/asset/point/cs) + 이벤트 전용 MSA(event-service)
- **인프라:** AWS Main(EKS, RDS PostgreSQL, ElastiCache) / GCP Pilot Light DR(Cloud SQL 상시 복제, GKE 장애 시 생성)
- **자동화:** Terraform(인프라) + ArgoCD(배포, GitOps) + GitHub Actions(CI)
- **목표 수치:** RTO ≤ 30분, RPO ≤ 5초 (near-zero, **"RPO 0"이라고 쓰지 않는다**)
- **레포:**
  | 레포 | 역할 |
  |---|---|
  | `point-infra` | Terraform, K8s 매니페스트, CDC, DR, **설계 문서·ADR의 원본** |
  | `point-backend` | Spring Boot (core-service, event-service), OpenAPI 명세 |
  | `point-frontend` | React + TypeScript SPA |
- **팀원 GitHub 계정:** `msugr`, `ZZGG2`, `didhddl49`, `sia9876`, `bbben2`. assign·멘션에는 이 계정만 쓴다. 사용자가 이름으로 말해서 어느 계정인지 모르면 추측하지 말고 계정을 묻는다.

## 2. 결정된 사항은 바꾸지 않는다 (Decision Lock)

아래는 팀이 ADR로 확정한 사항이다. **AI는 이를 대체하는 제안·구현을 하지 않는다.** 바꿔야 할 이유가 있으면 코드 대신 "ADR 제안이 필요합니다"라고 사용자에게 알린다.

| 영역 | 확정 사항 | 근거 |
|---|---|---|
| 아키텍처 | event 도메인만 MSA, 나머지는 core-service | ADR-0001 |
| 확장 | EKS + Karpenter + KEDA (Lambda, ECS, ASG 도입 금지) | ADR-0002 |
| 트래픽 진입 | Gateway API (AWS: ALB / GCP: GKE Gateway), 프론트는 web 파드 | ADR-0014, 0015 |
| DR | GCP Pilot Light, DR 시 core-service만 복구 | ADR-0003, 0004 |
| 복제 | PostgreSQL 네이티브 논리 복제 (비동기, PUBLICATION → SUBSCRIPTION) | ADR-0020 |
| DB | PostgreSQL 16 (RDS / Cloud SQL) | ADR-0006, 0013 |
| 이벤트 판정 | Redis Lua 원자 처리 (DB 락 사용 금지) | ADR-0007 |
| 원장 반영 | Redis Stream 비동기 (consumer group) + 멱등키 | ADR-0019 |
| 역할 분리 | Terraform = 클라우드 + ArgoCD 설치까지 / 나머지 K8s = ArgoCD | ADR-0009 |
| DR 독립성 | DR 경로에서 AWS 리소스 참조 금지 | ADR-0010 |
| 네트워크 | AWS `10.10.0.0/16`, GCP `10.20.0.0/16` 등 CIDR 표 변경 금지 | network-design.md |
| 언어/버전 | Java 21, Spring Boot 4.x, Node 20 LTS, TypeScript strict | 각 레포 README, ADR-0021 |

## 3. 작업 범위 규칙 (충돌 방지의 핵심)

1. **이슈 범위 밖 파일은 수정하지 않는다.** "하는 김에" 리팩터링, 이름 변경, 포맷 일괄 변경 금지.
2. **전역 영향 변경 금지 (사람이 별도 이슈로만):**
   - 의존성 추가·업그레이드 (`build.gradle`, `package.json`, provider 버전)
   - 린터/포매터 설정 변경
   - 공통 모듈(`common/`, `shared/`) 및 공통 타입 변경
   - 디렉터리 구조 이동, 패키지명 변경
   - DB 스키마 변경(Flyway 파일 추가는 허용, **기존 마이그레이션 파일 수정은 금지**)
3. **한 PR = 한 목적.** 기능 + 리팩터링 + 포맷을 섞지 않는다.
4. **생성 파일을 커밋하지 않는다.** (빌드 산출물, lock 외 자동생성 코드, `.terraform/`)
5. 기존 코드의 패턴을 먼저 찾아 **그대로 따른다.** 새로운 패턴(새 라이브러리, 새 레이어)을 임의로 도입하지 않는다.

## 4. 절대 금지 (Hard Stop)

AI는 아래를 **제안하거나 실행하지 않는다.** 사용자가 요청해도 위험을 설명하고 멈춘다.

- 시크릿·키·비밀번호·토큰·계정 ID를 코드, 설정, 커밋, 로그, 예시에 하드코딩 (예시에는 `CHANGE_ME` 사용)
- `terraform apply` / `destroy`, `kubectl apply/delete` 를 로컬에서 실제 환경에 실행 (적용은 CI 파이프라인만)
- `git push --force` (본인 feature 브랜치의 `--force-with-lease` 는 예외), `main` 직접 push
- 테스트를 통과시키기 위해 테스트를 삭제·`@Disabled`·skip 처리
- `prevent_destroy`, `deletion_protection`, 브랜치 보호, 보안 스캔 비활성화
- 보안그룹/방화벽 `0.0.0.0/0` 인바운드 추가 (ALB 443 제외)
- 운영 DB 데이터를 수정하는 SQL 작성 (마이그레이션 외)
- 포인트 원장(`point_ledger`) UPDATE/DELETE 로직 (append-only 원칙)

## 5. 코드·문서 공통 규칙

| 항목 | 규칙 |
|---|---|
| 언어 | 코드 식별자는 영어, 주석·문서·커밋 메시지 본문은 한국어 허용 |
| 커밋 | Conventional Commits: `type(scope): 요약` — type: feat, fix, infra, docs, test, refactor, chore, ci |
| 브랜치 | `type/#이슈번호-짧은-설명` 예: `feat/#42-quiz-lua` |
| 설정값 | 환경별 값은 환경 변수로 주입, 코드에 URL·계정·리전 하드코딩 금지 |
| 테스트 | 새 로직에는 테스트를 함께 작성. 테스트 없이 PR 불가 (문서/설정 변경 제외) |
| TODO | `TODO(#이슈번호): 설명` 형식. 이슈 번호 없는 TODO 금지 |
| 문서 동기화 | 동작·구조가 바뀌면 관련 문서(docs/, README, OpenAPI)를 **같은 PR**에서 수정 |
| 시간 | 날짜·시각은 **KST(UTC+9)** 로 쓰고 `KST`를 명시한다 (예: `2026-11-20 14:00 KST`). 로그·서버의 UTC 값은 KST로 변환해 쓴다 |
| 클라우드 중립 | 앱 코드에서 AWS/GCP SDK 직접 호출 금지 → 인터페이스 뒤에 숨김 (DR 시 같은 이미지가 GCP에서 동작해야 함) |

## 6. 불확실할 때의 행동

1. 추측으로 구현하지 않는다. **가정을 명시**하거나 사용자에게 질문한다.
2. 문서와 코드가 다르면 **문서(ADR)가 우선**이며, 불일치를 사용자에게 보고한다.
3. 여러 방법이 가능하면 기존 ADR/코드와 가장 일관된 방법 하나를 고르고, 이유를 한 줄로 남긴다.
4. 존재하지 않는 API·라이브러리 옵션·Terraform 속성을 만들어내지 않는다. 확신이 없으면 "공식 문서 확인 필요"라고 표시한다.

## 7. AI 출력물 제출 규칙

- PR 템플릿의 **"AI 사용"** 체크박스를 반드시 표시한다.
- AI가 생성한 코드는 **작성자가 한 줄씩 이해하고 설명할 수 있어야 머지 가능.** (리뷰에서 "AI가 짠 거라 모름"은 반려 사유)
- AI가 제안한 설계 변경은 코드가 아니라 **ADR 초안 이슈**로 올린다.
- 커밋 메시지·PR 본문·이슈·코멘트에 AI 생성 서명 문구를 넣지 않는다. (예: `Generated with Claude Code`, `🤖 Generated with ...`, `Co-Authored-By: Claude ...`) AI 사용 여부는 PR 템플릿의 **"AI 사용"** 체크박스로만 표시한다. 도구 기본값이 서명을 붙이면 제출 전에 삭제한다.

## 8. 작업 시작 전 AI가 읽어야 할 문서

| 작업 | 먼저 읽을 문서 (point-infra/docs 기준) |
|---|---|
| 모든 작업 | 이 문서(특히 **§9 작업 시작·종료 절차**), 해당 레포 `AGENTS.md` 하단의 레포별 규칙 |
| 이슈·PR·보드 | `docs/team/github-workflow.md` |
| 백엔드 도메인 | `01-architecture/hybrid-msa.md`, `03-development/domain-model.md`, `api-spec.md` |
| 이벤트/Redis/원장 반영 | `02-adr/0007`, `0019`, `01-architecture/data-architecture.md` |
| Terraform | `04-infrastructure/terraform-guide.md`, `01-architecture/network-design.md` |
| K8s/배포 | `04-infrastructure/cicd-pipeline.md`, `02-adr/0009` |
| DR 관련 | `06-disaster-recovery/*`, `02-adr/0010`, `0011` |
| 프론트 API 연동 | `point-backend/api/openapi.yaml` (직접 타입 작성 금지, 생성 타입 사용) |

## 9. 작업 시작·종료 절차 (Start / End)

> 목적: 다른 팀원이 이미 했거나 하고 있는 일을 **AI가 중복해서 하거나, 충돌하는 변경을 만들거나, 남의 작업을 지우는 것**을 막는다.
> 모든 작업은 **START(9.2)로 시작하고 END(9.4)로 끝난다.** 요청이 작아 보여도 생략하지 않는다.
> 이슈를 매번 사용자에게 출력할 필요는 없다. 확인은 AI가 하고, **결과는 발견이 있을 때만** 보고한다. 발견이 없으면 "겹치는 작업 없음" 한 줄로 끝낸다.

### 9.1 전제와 대상

- 대상 조직은 `JWDJM`, 보드는 `aws3team-final-board` (project 번호 `1`).
- `gh` 설치 + 로그인 + scope(`repo`, `read:org`, `project`)가 필요하다. 확인: `gh auth status`. 하나라도 빠지면 **작업을 시작하지 않고** 사용자에게 알린다.
- **모든 `gh` 명령에 `-R JWDJM/<레포>`를 붙인다.** (fork에서 `gh pr create`가 상위 레포로 향하는 것과, 기본 레포 미설정 오류를 막기 위함)
- 이 레포들은 **Public**이다. 이슈·PR·코멘트에 시크릿, 계정 ID, 내부 IP를 쓰지 않는다 (§4와 동일).

### 9.2 START — 작업 시작 전 (파일 수정, 리소스·이슈 생성 전에 수행)

**Step 1. 충돌 확인 (읽기 전용).** 요청에서 키워드를 뽑아 실행한다. 작업이 여러 레포에 걸치면 각 레포에서 실행한다.

```bash
git fetch origin
gh issue list -R JWDJM/<레포> --state all --search "<키워드>" --limit 20
gh pr list    -R JWDJM/<레포> --state all --search "<키워드>" --limit 20
gh pr list    -R JWDJM/<레포> --state open --json number,title,author,files
git log origin/main -n 5 --format="%h %an %ad %s" --date=short -- <수정·삭제할 경로>
```

**Step 2. 결과에 따른 행동.**

| 발견 | AI의 행동 |
|---|---|
| 이미 닫힌 이슈 또는 머지된 PR이 같은 일을 함 | **중단.** 사실을 알리고, 새로 만들지 않고 확장할지 묻는다 |
| 같은 내용의 이슈가 **다른 사람에게 assign**됨 | **중단.** 담당자를 알리고 사용자에게 묻는다 |
| open PR이 **같은 파일**을 수정 중 | **중단.** PR 번호·작성자·겹치는 파일을 알린다 |
| 다른 사람이 최근 수정한 파일·리소스를 삭제·이름 변경하려 함 | 실행 전에 사용자에게 묻는다 |
| 같은 내용의 open 이슈가 이미 있음 (assign 없음 또는 본인) | 그 이슈를 사용한다. 새로 만들지 않는다 |
| 겹치는 것이 없음 | 진행하고 "겹치는 작업 없음"이라고 한 줄로 알린다 |

**Step 3. 이슈 확보.** 모든 작업에는 이슈가 있어야 한다 (시간 기준 예외 없음).

- 기존 이슈가 있으면 그 번호를 쓴다.
- 없으면 제목·본문·소속 goal(parent)을 **초안으로 보여주고 사용자 확인을 받은 뒤** 만든다. 확인 없이 만들지 않는다.
- 제목은 구체적인 명사로 쓴다. (좋음: "EKS managed node group 추가" / 나쁨: "수정", "업데이트")
- 큰 목표는 goal(parent) 이슈 하나로 만들고, 세부 할 일은 그 아래 **sub-issue**로 만든다. 세부 할 일마다 최상위 이슈를 만들지 않는다.

```bash
# 이슈 생성 (URL이 출력된다)
URL=$(gh issue create -R JWDJM/<레포> --title "<제목>" --body "<본문>")

# 보드에 추가. point-infra는 자동 추가되므로 생략 가능, frontend/backend는 필수
gh project item-add 1 --owner JWDJM --url "$URL"

# sub-issue로 연결 (CHILD, PARENT는 이슈 번호)
ID=$(gh api repos/JWDJM/<레포>/issues/CHILD --jq '.id')
gh api --method POST repos/JWDJM/<레포>/issues/PARENT/sub_issues -F sub_issue_id=$ID --silent
```

> `gh issue create --project`는 사용하지 않는다. (org에서 Projects classic 조회 오류가 난다)

**Step 4. 담당 표시.** `gh issue edit <번호> -R JWDJM/<레포> --add-assignee @me`

**Step 5. 브랜치.** `type/#이슈번호-짧은-설명` (§5).

### 9.3 보드 상태 (Status)

| Status | 의미 | 바뀌는 방법 |
|---|---|---|
| Backlog | 발견했지만 아직 계획에 없음 (새 이슈의 기본값) | 자동 |
| Todo | 이번 주에 할 일 | **사람이 이동** |
| In Progress | 진행 중 | PR이 이슈에 연결되면 **자동** |
| Done | 완료 | 이슈가 닫히면 **자동** |

- AI는 보드 상태를 직접 바꾸지 않는다. 위 자동 동작에 맡긴다.
- 보드의 기본 뷰는 `Goals` (`no:parent-issue`)다. goal만 보이고 sub-issue는 goal 안의 진행률로 확인한다.

### 9.4 END — 작업 종료 시

1. **PR 생성 전에 사용자에게 묻는다** ("PR을 만들까요?"). 머지는 사용자가 명시적으로 지시할 때만 한다.
2. PR은 `gh pr create -R JWDJM/<레포>`로 만든다. 본문에 반드시 포함:
   - `Closes #이슈번호` (PR 연결 → In Progress 자동 전환)
   - **변경한 파일 / Terraform 리소스 목록** (다음 AI의 Step 1 충돌 확인이 이 정보로 동작한다)
   - "AI 사용" 체크박스 표시 (§7)
3. 끝내지 못한 일이 있으면 sub-issue로 만들 것을 **한 번만 제안**하고, 사용자가 동의하면 만든다.
4. goal의 마지막 sub-issue가 닫히면 **goal 이슈를 닫을지 사용자에게 묻는다.** (parent는 자동으로 닫히지 않는다)
5. 사용자에게 마지막으로 보고한다: 변경한 파일, 세운 가정, 남은 TODO(`TODO(#이슈번호)`).

### 9.5 다른 사람의 항목

- 다른 사람의 이슈·PR에는 **코멘트만** 남길 수 있다. **close, delete, reassign, 본문 수정은 하지 않는다.**
- 이슈를 만들기 전에는 반드시 Step 1의 검색을 먼저 한다 (중복 생성 금지).
- 보드 설정, 라벨 정의, 워크플로 변경은 사람이 한다.

<!-- ====================== COMMON RULES END (v1.5.0) ====================== -->

# 레포별 규칙 — point-infra

## 이 레포의 범위
Terraform, K8s 매니페스트(GitOps 원천), DR 복제 SQL(`cdc/`, 논리 복제), DR 스크립트, 부하 테스트, **설계 문서·ADR**, 팀 공통 규칙 원본(`team/`).

## Terraform
- `modules/`에는 **provider·backend 블록을 두지 않는다.** provider는 `envs/*`에서만 선언.
- 모든 변수에 `description`, 타입 명시. 민감 값은 `sensitive = true`.
- 공통 태그/라벨(`project`, `env`, `managed-by`, `cost-center`)을 반드시 적용.
- `envs/gcp-dr-*`에서 **S3 backend, `terraform_remote_state`(S3), AWS provider 사용 금지** (ADR-0010).
- `envs/gcp-dr-standby`의 Cloud SQL·Static IP에는 `prevent_destroy = true` 유지.
- 리소스 이름 변경 시 `moved {}` 블록을 함께 작성 (재생성 방지).
- 변경 전 `terraform fmt -recursive`, PR에 plan 결과 첨부 필수 (CI가 자동 코멘트).
- **동일 `envs/<env>` 디렉터리를 두 명이 동시에 작업하지 않는다.** 착수 전 이슈에 `env:<이름>` 라벨 + 담당자 지정으로 선점.

## Kubernetes / GitOps
- 구조: `k8s/base` (환경 공통) → `k8s/overlays/{aws,gcp-dr}` (환경 차이만). base에 환경 특정 값 금지.
- **`overlays/gcp-dr`에 event-service를 추가하지 않는다** (선택적 복구, ADR-0004).
- 이미지 태그(`images:` newTag)는 **사람·AI가 직접 수정하지 않는다.** backend CI 봇의 태그 bump PR만 허용.
- 모든 Deployment: resources.requests, readiness/liveness probe, PDB, non-root securityContext 필수.

## 문서 / ADR
- 새 ADR 번호는 `docs/02-adr/README.md` 표의 마지막 번호 + 1. 번호 충돌 시 나중에 머지되는 PR이 번호를 올린다.
- **Accepted ADR 본문은 수정하지 않는다.** 결정이 바뀌면 새 ADR을 쓰고 기존 ADR 상태를 `Superseded by ADR-XXXX`로만 변경.
- `team/ai/AGENTS.common.md` 수정 시 버전(`vX.Y.Z`)을 올리고 `make sync-ai-rules` 후 각 레포에 동기화 PR 생성.
