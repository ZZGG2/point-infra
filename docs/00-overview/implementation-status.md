# 구현 현황 (설계 ↔ 코드)

> 기준: 2026-11-23 KST · point-infra `main` c8a3761 · point-backend `ae2c653` · point-frontend `b21f1a8`
> 다른 문서는 **목표 설계(ADR)** 기준으로 쓰여 있다. 이 문서는 "그중 무엇이 실제 코드로 있는가"만 기록한다.
> 문서와 코드가 다르면 ADR 이 우선이다 (AGENTS.md §6) — 아래 ❌/🟡 는 "문서를 고칠 곳"이 아니라 **구현할 곳**이다.
> 상태: ✅ 구현 · 🟡 일부/스텁 · ❌ 없음

## 1. 한눈에 보기

| 영역 | 상태 | 요약 |
|---|---|---|
| 애플리케이션 (point-backend) | ✅ 핵심 경로 | 회원가입·로그인(JWT + refresh token), 잔액·내역·사용, 출석, 퀴즈(즉시 지급, ADR-0018), 원장 반영 Redis Stream(Lua 판정 + `XADD`, consumer group·재시도·DLQ·7일 보존, ADR-0019), 운영 API. asset·cs·대기열·환불은 없음 |
| 프론트엔드 (point-frontend) | ✅ 핵심 화면 | 로그인/가입, 홈, 이벤트, 결제, 내역, 관리자(이벤트 현황은 조회 전용) |
| Terraform (AWS) | 🟡 | vpc, eks, DB 모듈(ADR-0006 기준 — RDS 로 교체 예정) 작성. karpenter·elasticache·ecr·edge 는 스텁, `argocd-bootstrap` 없음 |
| Terraform (GCP) | 🟡 | argocd-bootstrap 작성. network·cloudsql·gke·vpn 스텁 |
| K8s / GitOps | 🟡 | base(core-service, event-service, maintenance), overlays, argocd apps 일부. Gateway API(Gateway·HTTPRoute) 매니페스트 ✅, web·db-init·ExternalSecret 없음 |
| CI/CD | 🟡 | backend·frontend `ci.yml`(테스트·빌드·Trivy), infra `terraform-plan.yml`(정적 검증). 이미지 push·태그 bump·apply·drift 는 TODO |
| DR 복제 (`cdc/`) | ✅ 설정 SQL | 논리 복제 Publication(RDS)·Subscription(Cloud SQL) SQL (ADR-0020). 적용 자동화·sg-rds 규칙·RDS 파라미터(pg_cron, `max_slot_wal_keep_size`)는 없음 |
| DR 자동화 | 🟡 | `dr-failover.yml` 단계 골격, SQL 2종(시퀀스·지갑) 작성. 셸 스크립트 5종은 TODO |
| 부하 테스트 | 🟡 | k6 S2·S3 만, **`X-User-Id` 헤더 기반이라 현재 JWT 인증과 맞지 않음** |
| 관측성 | 🟡 | 앱이 `/actuator/prometheus` 노출. kube-prometheus-stack·Fluent Bit·대시보드·알람 없음 |

## 2. 인프라

### 2.1 Terraform 모듈 (`infra/terraform`)
| 모듈 | 상태 | 비고 |
|---|---|---|
| `bootstrap/aws`, `bootstrap/gcp` | ✅ | S3 / GCS state 버킷 |
| `modules/aws/vpc` | ✅ | terraform-aws-modules/vpc `~> 5.0`. VPC Endpoint(ecr·sts·secretsmanager·logs)는 TODO |
| `modules/aws/eks` | ✅ | terraform-aws-modules/eks `~> 20.0`. API 엔드포인트 public(허용 CIDR 제한 TODO) |
| DB 모듈 (현재 스캐폴딩) | 🟡 | ADR-0006(Superseded) 기준 클러스터형 DB 모듈. ADR-0013 의 `modules/aws/rds` (RDS for PostgreSQL 16) 로 교체 예정 — AWS DB 영역은 #8 담당자가 개인 샌드박스에서 검증 중 ([infra/terraform/README](../../infra/terraform/README.md)) |
| `modules/aws/karpenter`, `elasticache`, `ecr` | 🟡 스텁 | `# TODO: 구현 예정` 만 있음 |
| `modules/aws/edge` | 🟡 스텁 | 목표는 `modules/aws/waf` (ADR-0014, 0015 — CloudFront 미사용) |
| `modules/aws/argocd-bootstrap` | ❌ | ADR-0009 (EKS 쪽 ArgoCD + root Application) |
| `modules/gcp/argocd-bootstrap` | ✅ | helm_release + root Application |
| `modules/gcp/network`, `cloudsql`, `gke`, `shared/vpn` | 🟡 스텁 | |
| `envs/aws-main` | 🟡 | vpc + eks + DB 모듈(교체 예정) 조립. karpenter·elasticache·ecr·edge·vpn 은 TODO 주석 |

### 2.2 K8s / GitOps (`k8s/`)
| 항목 | 설계 | 현재 | 근거 |
|---|---|---|---|
| 트래픽 진입 | Gateway + HTTPRoute (`/api/events` → event-service, `/api` → core-service, `/` → web) | 🟡 `overlays/{aws,gcp-dr}/gateway.yaml` ✅ (HTTP 80 리스너, AWS: `LoadBalancerConfiguration`·`TargetGroupConfiguration`, GCP: `HealthCheckPolicy`). **적용 전 필요**: Terraform sg-alb(`point-main-alb`)·LBC Pod Identity IAM(#8 영역), GKE Gateway API 활성화(gke 모듈 스텁), `/` → web 은 #15 전까지 backend 없음. HTTPS 443 은 도메인·ACM 후 | ADR-0014 |
| 프론트 | `k8s/base/web` (nginx 파드) | ❌ 없음 | ADR-0015 |
| DB 초기화 | `overlays/aws/db-init.yaml` (`app_rw` 생성 Sync Job) | ❌ 없음 | ADR-0013 |
| 시크릿 | ExternalSecret `core-service-db` (+ event-service 공개키) | ❌ 매니페스트 없음 (`platform/external-secrets/README.md` 에 키 목록만) | ADR-0010 |
| event-service 시크릿 | `JWT_PUBLIC_KEY` 주입 | ❌ base deployment 에 `secretRef` 없음 → aws 프로필에서 **기동 실패** (공개키·JWKS URI 둘 다 없으면 예외) | — |
| 앱 설정 | Redis 주소 등 | ❌ overlay ConfigMap 에 `REDIS_HOST` 없음 (기본값 localhost) — core-service(원장 반영 Stream)·event-service 둘 다 필요, elasticache 모듈 스텁이라 엔드포인트 없음. `REWARD_STREAM_ENABLED` 는 ✅ (aws=true, gcp-dr=false) | ADR-0019 |
| 플랫폼 Application | LBC, ESO, KEDA, Karpenter, 모니터링 | 🟡 `argocd/aws/apps.yaml` 에 apps-aws·karpenter-nodepools·aws-load-balancer-controller(차트 3.6.3 + Gateway API CRD v1.6.0 + GatewayClass, `platform/gateway/aws`). ESO·KEDA·모니터링 TODO | ADR-0009, 0014 |
| Sync Window | 이벤트 시간 배포 금지 | ✅ `argocd/aws/sync-window.yaml` | |
| KEDA | Cron + CPU (event-service), Redis Stream pending (core-service) | 🟡 event-service ScaledObject ✅, core-service Stream 트리거 ❌ | ADR-0002, 0019 |
| maintenance (DR) | `/api/events/**` 503 | ✅ `base/maintenance` (nginx, LB 헬스체크용 `/healthz` 200) | ADR-0004 |
| PDB / probe / non-root | 모든 Deployment 필수 | ✅ core-service·event-service base | AGENTS.md |

### 2.3 CI/CD (`.github/workflows`, 각 레포)
| 워크플로 | 상태 | 비고 |
|---|---|---|
| backend `ci.yml` | 🟡 | Gradle test(Testcontainers·ArchUnit) ✅, 이미지 빌드 + Trivy ✅, **ECR·AR 이중 푸시와 infra 태그 bump PR 은 `echo TODO`** |
| frontend `ci.yml` | 🟡 | lint·typecheck·test·build ✅, web 이미지 빌드 + Trivy ✅, 푸시·bump 는 TODO |
| infra `terraform-plan.yml` | 🟡 | fmt·tflint·checkov(soft fail)·`init -backend=false`·validate ✅. 원격 plan 은 `vars.TF_PLAN_ENABLED` 일 때만, PR 코멘트 TODO |
| infra `pr-title-lint.yml` | ✅ | Conventional Commits |
| infra `terraform-apply.yml`, `drift-detect.yml` | ❌ | [cicd-pipeline](../04-infrastructure/cicd-pipeline.md) 표에만 있음 |
| infra `dr-failover.yml` | 🟡 | 승인 환경·단계 골격 ✅, 호출하는 스크립트가 TODO |
| infra `dr-failback.yml` | 🟡 | 골격 |

### 2.4 DR 스크립트 (`scripts/dr`)
| 파일 | 상태 |
|---|---|
| `fix-sequences.sql`, `reconcile-wallet.sql` | ✅ |
| `promote-cloudsql.sh`, `record-rpo.sh`, `wait-ready.sh`, `smoke-test.sh`, `switch-dns.sh` | 🟡 TODO (`switch-dns.sh` 는 ADR-0016 결정 대기) |

## 3. 애플리케이션

### 3.1 API (point-backend 기준, 상세는 [api-spec](../03-development/api-spec.md))
| 구분 | 구현됨 | 설계에 있으나 없음 |
|---|---|---|
| 인증 | `signup`, `login`, **`refresh`, `logout`**, `jwks.json`, `GET /api/users/me` | 관리자 역할(JWT role) |
| 포인트 | `balance`, `history`(최근 20건), `use`(Idempotency-Key) | `history?cursor=` 페이지네이션, `POST /api/points/refunds` |
| asset / cs | — | `GET /api/assets`, `GET /api/cs/notices` (프론트 폴더도 비어 있음) |
| 이벤트 | `attendance`, `{id}/answers` | `GET /api/events/active`, 대기열 `{id}/queue`, `{id}/queue/me` |
| 이벤트 운영 | 생성 `POST /api/events/admin/{id}`(`X-Admin-Token`), 현황 `{id}/status`, local 전용 `{id}/open` | 시작 시각 예약 생성 Job, 관리자 역할(JWT role) |
| 운영·헬스 | `/api/system/{info,whoami,ledger}`, `/api/events/system/{info,whoami}`, `/api/health`, actuator | |

### 3.2 데이터·도메인
| 항목 | 상태 | 비고 |
|---|---|---|
| 스키마 (Flyway) | ✅ | users(app_user, user_credential, **refresh_token**), asset.linked_account, point(wallet, ledger, refund_request, reward_pending·event_settlement — ADR-0018 로 미사용), cs.notice, public.dr_heartbeat |
| `cs.inquiry`, `asset.asset_snapshot` | ❌ | [data-architecture](../01-architecture/data-architecture.md) 표에만 있음 |
| 원장 append-only + 멱등키 | ✅ | 원장 UPDATE/DELETE 코드 없음, `idempotency_key` UNIQUE, 동시성 테스트 있음 |
| 지갑 동시성 | ✅ | **비관적 락** (`SELECT ... FOR UPDATE`). `version` 컬럼은 증가만 하고 낙관적 락 판정에는 쓰지 않음 |
| 취소·환불·만료 | ❌ | `LedgerType` 에 `REFUND, EXPIRE, CANCEL` 정의만, `refund_request` 테이블만 존재 |
| 퀴즈 즉시 지급 (ADR-0018, ADR-0017 철회) | ✅ | consumer 테스트 (퀴즈·출석 즉시 반영, 키 길이 검증) |
| 대사 배치 (일 1회) | ❌ | 출석 비트맵↔원장, 지갑↔원장 합계, RDS↔Cloud SQL — [domain-model §4](../03-development/domain-model.md). DR 전환용 `reconcile-wallet.sql` 만 있음 |
| Redis 키 (ADR-0007) | 🟡 | 실제 키: `event:{id}:stock`·`participants`·`winners`·`amount` (`{id}` 는 클러스터 해시태그), `attendance:{yyyyMMdd}` Bitmap(TTL 2일, `{날짜}` 해시태그), 보상 Stream `event:{id}:rewards`·`attendance:{yyyyMMdd}:rewards`, 등록 Set `reward:streams`, DLQ `reward:dlq` (ADR-0019). `reward:streams` 의 종료된 이벤트 정리는 없음. 이벤트 키 TTL = 마감(`event:{id}:ends`) + 1일 (운영 생성 API 만 설정, 보상 Stream 제외). **`event:{id}:queue` 없음** |

### 3.3 인증·세션
| 항목 | 상태 | 비고 |
|---|---|---|
| access token | ✅ | RS256 JWT 15분, 브라우저 메모리. event-service 는 공개키(`JWT_PUBLIC_KEY`) 또는 JWKS 로 자체 검증 |
| refresh token | ✅ | 256bit 랜덤 14일, DB 에 SHA-256 해시만, **재발급 시 교체(rotation)**, HttpOnly·SameSite=Strict 쿠키(`Path=/api/auth`), 로그아웃 시 폐기. DR 복제 대상 아님 (Failover 후 재로그인) |
| 프론트 연동 | ✅ | 401 → refresh 1회 재시도(동시 호출 합침), 새로고침 시 복원 |
| 재사용 탐지 (token family 폐기) | ❌ | 폐기된 refresh 토큰 재사용 시 401 만 |
| 서명 키 교체 (`kid`, 다중 키 JWKS) | ❌ | 키 1개 |
| 프론트 이벤트 화면 | ✅ | `GET /api/events/{id}/status` 만 호출 (모든 프로필). 관리자 패널은 조회 전용 — 이벤트 생성은 event-day 런북의 관리자 API (point-frontend#4) |

## 4. 테스트
| 레벨 | 상태 | 비고 |
|---|---|---|
| Unit / Integration (Testcontainers) | ✅ | 인증 흐름, JWT, 멱등성 동시성, consumer, Redis 동시성(출석·퀴즈) |
| Architecture (ArchUnit) | ✅ | `ModuleBoundaryTest` |
| IaC | 🟡 | 정적 검증만 (원격 plan 비활성) |
| Load (k6) | 🟡 | S2·S3 스크립트만, 인증이 `X-User-Id` 헤더 → **JWT(`Authorization: Bearer`) 로 전환 필요**. S1·S4~S6 없음 |
| Chaos / DR 훈련 | ❌ | 기록 없음 |
| 세션 유지 (파드 축소·롤링 중 로그인 유지) | ❌ | 시나리오 미정의 |

## 5. 구현 시 참고 — EKS 검증 환경에서 확인된 사항
point-infra 밖의 검증 환경에서 실제로 구축하며 확인한 것. 이 레포에 구현할 때 같은 문제를 피하기 위한 메모.

| 항목 | 확인된 내용 |
|---|---|
| `app_rw` 권한 | Flyway 가 `app_rw` 로 스키마·테이블을 만든다 → `GRANT CONNECT, CREATE ON DATABASE` 와 함께 **PostgreSQL 15+ 는 `GRANT USAGE, CREATE ON SCHEMA public`** 도 필요 (없으면 `permission denied for schema public`) |
| db-init Job SQL | K8s 는 `command`/`args` 의 `$$` 를 `$` 로 바꾼다 → `DO $$` 대신 `DO $do$ ... $do$` |
| db-init 를 ArgoCD hook 으로 | PreSync Job 이 읽는 Secret 을 만드는 ExternalSecret 도 PreSync hook 이어야 한다 (일반 리소스는 hook 뒤에 생성 → 교착) |
| event-service 인증 | `JWT_PUBLIC_KEY` 가 `JWT_JWK_SET_URI` 보다 우선. 공개키는 core-service 개인키(PKCS#8)와 같은 쌍 |
| local 프로필 오버라이드 | `application-local.yml` 의 고정값이 `${ENV}` 자리표시자를 이긴다 → 속성 직접 지정 환경변수(하이픈 제거 — 예: `app.auth.cookie-secure` → `APP_AUTH_COOKIESECURE`) 사용 |
| Karpenter IAM | 컨트롤러 정책이 관리형 정책 한도(6,144자)를 넘음 → EKS 모듈 karpenter 서브모듈 `enable_inline_policy = true` |
| 노드 SG | EKS 모듈 기본 노드 간 허용은 1025-65535 + 53 → 컨테이너 포트는 1025 이상 사용 |
| DB 서브넷 라우트 | VPC 모듈은 `create_database_subnet_route_table = true` 가 아니면 Data 서브넷을 private(NAT) 라우트에 붙인다 → 3-Tier 격리 깨짐 |
| SG 규칙 `for_each` | 아직 생성 전인 SG ID 를 `for_each` 키로 쓰면 첫 plan 실패 → `count` |
