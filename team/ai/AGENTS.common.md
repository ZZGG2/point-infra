<!-- ===================== COMMON RULES START (v1.0.0) =====================
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
- **인프라:** AWS Main(EKS, Aurora PostgreSQL, ElastiCache, MSK) / GCP Pilot Light DR(Cloud SQL 상시 복제, GKE 장애 시 생성)
- **자동화:** Terraform(인프라) + ArgoCD(배포, GitOps) + GitHub Actions(CI)
- **목표 수치:** RTO ≤ 30분, RPO ≤ 5초 (near-zero, **"RPO 0"이라고 쓰지 않는다**)
- **레포:**
  | 레포 | 역할 |
  |---|---|
  | `point-infra` | Terraform, K8s 매니페스트, CDC, DR, **설계 문서·ADR의 원본** |
  | `point-backend` | Spring Boot (monolith, event-service), OpenAPI 명세 |
  | `point-frontend` | React + TypeScript SPA |

## 2. 결정된 사항은 바꾸지 않는다 (Decision Lock)

아래는 팀이 ADR로 확정한 사항이다. **AI는 이를 대체하는 제안·구현을 하지 않는다.** 바꿔야 할 이유가 있으면 코드 대신 "ADR 제안이 필요합니다"라고 사용자에게 알린다.

| 영역 | 확정 사항 | 근거 |
|---|---|---|
| 아키텍처 | event 도메인만 MSA, 나머지는 monolith | ADR-0001 |
| 확장 | EKS + Karpenter + KEDA (Lambda, ECS, ASG 도입 금지) | ADR-0002 |
| DR | GCP Pilot Light, DR 시 monolith만 복구 | ADR-0003, 0004 |
| 복제 | Debezium CDC (비동기) | ADR-0005 |
| DB | PostgreSQL 16 (Aurora / Cloud SQL) | ADR-0006 |
| 이벤트 판정 | Redis Lua 원자 처리 (DB 락 사용 금지) | ADR-0007 |
| 원장 반영 | Kafka 비동기 + 멱등키 | ADR-0008 |
| 역할 분리 | Terraform = 클라우드 + ArgoCD 설치까지 / 나머지 K8s = ArgoCD | ADR-0009 |
| DR 독립성 | DR 경로에서 AWS 리소스 참조 금지 | ADR-0010 |
| 네트워크 | AWS `10.10.0.0/16`, GCP `10.20.0.0/16` 등 CIDR 표 변경 금지 | network-design.md |
| 언어/버전 | Java 21, Spring Boot 3.x, Node 20 LTS, TypeScript strict | 각 레포 README |

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

## 8. 작업 시작 전 AI가 읽어야 할 문서

| 작업 | 먼저 읽을 문서 (point-infra/docs 기준) |
|---|---|
| 모든 작업 | 이 문서, 해당 레포 `AGENTS.md` 하단의 레포별 규칙 |
| 백엔드 도메인 | `01-architecture/hybrid-msa.md`, `03-development/domain-model.md`, `api-spec.md` |
| 이벤트/Redis/Kafka | `02-adr/0007`, `0008`, `01-architecture/data-architecture.md` |
| Terraform | `04-infrastructure/terraform-guide.md`, `01-architecture/network-design.md` |
| K8s/배포 | `04-infrastructure/cicd-pipeline.md`, `02-adr/0009` |
| DR 관련 | `06-disaster-recovery/*`, `02-adr/0010`, `0011` |
| 프론트 API 연동 | `point-backend/api/openapi.yaml` (직접 타입 작성 금지, 생성 타입 사용) |

<!-- ====================== COMMON RULES END (v1.0.0) ====================== -->
