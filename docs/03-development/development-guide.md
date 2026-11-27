# 개발 가이드

## 1. 기술 스택

| 영역 | 선택 | 버전 (고정) |
|---|---|---|
| 언어 / 런타임 | Java (Temurin) | 21 LTS |
| 프레임워크 | Spring Boot | 4.x (현재 4.1.3, ADR-0021) |
| 빌드 | Gradle (wrapper) | 9.x (현재 9.9.0) |
| DB 마이그레이션 | Flyway | - |
| 테스트 | JUnit 5, Testcontainers, ArchUnit | Testcontainers 1.21.x, ArchUnit 1.5.x |
| 컨테이너 | Docker (multi-stage, `eclipse-temurin:21-jre`, non-root uid 10001) · web 은 `nginx-unprivileged` | - |
| 로컬 인프라 | Docker Compose (PostgreSQL 16, Redis 7) | - |
| 부하 테스트 | k6 | - |
| 프론트엔드 | React 18 + Vite + TypeScript (strict), TanStack Query, openapi-typescript | Node 20 LTS |

## 2. 로컬 개발 환경 (point-backend 레포)

```bash
make local-up           # docker compose up -d
make run-core       # http://localhost:8080
make run-event          # http://localhost:8081
make local-down
```

| 서비스 | 포트 |
|---|---|
| core-service | 8080 |
| event-service | 8081 |
| PostgreSQL | 5432 |
| Redis | 6379 |

## 3. 브랜치 · 커밋 · PR 규칙

팀 공통 규칙 문서로 일원화: [docs/team/github-workflow.md](../team/github-workflow.md)

## 4. 레포 구성

| 레포 | 내용 |
|---|---|
| point-infra | 인프라, GitOps, 문서 (이 레포) |
| point-backend | core-service, event-service, OpenAPI |
| point-frontend | React + Vite + TypeScript SPA |

## 5. 코드 규칙

- 모듈 경계: [hybrid-msa.md §3](../01-architecture/hybrid-msa.md) — ArchUnit 테스트로 강제
- 설정: 환경별 값은 `application-{profile}.yml` 이 아니라 **환경 변수 / K8s ConfigMap·Secret** 으로 주입 (12-Factor)
- 프로필: `local`, `aws`, `gcp-dr` — 프로필 전용 설정 파일은 **`application-local.yml` 만** 있다 (데모 시드, local 전용 이벤트 API, 쿠키 Secure 끔, JWT 키 없으면 임시 키 생성). aws·gcp-dr 은 파일 없이 환경 변수만으로 설정한다
- ⚠️ `application-local.yml` 의 고정값은 `${ENV}` 자리표시자를 이긴다 → local 프로필로 클러스터에 띄울 땐 속성을 직접 가리키는 환경 변수(예: `APP_AUTH_COOKIESECURE`)로 덮는다
- 인증: access token RS256 JWT + refresh token(HttpOnly 쿠키, rotation) — [api-spec §인증 방식](api-spec.md#인증-방식). 운영 프로필에서는 `JWT_PRIVATE_KEY`(core-service, PKCS#8) 가 없으면 기동 실패. event-service 는 `JWT_PUBLIC_KEY` 또는 `JWT_JWK_SET_URI` 중 하나가 필요하며 (`JWT_PUBLIC_KEY` 우선), 둘 다 없으면 기동 실패
- 헬스체크: `/actuator/health/liveness`, `/actuator/health/readiness` 분리
- Graceful Shutdown: `server.shutdown=graceful`, preStop sleep 10s (ALB 등록 해제 대기)

## 6. DR 모드 고려 코딩 규칙

| 규칙 | 이유 |
|---|---|
| 클라우드 SDK 직접 호출 금지 (S3 등은 추상화 인터페이스 뒤로) | GCP에서도 같은 이미지가 동작해야 함 |
| Redis 미연결 시에도 core-service 기동 가능 (gcp-dr 오버레이의 `REWARD_STREAM_ENABLED=false` 가 원장 Stream consumer·Redis health·점검을 끈다, ADR-0019) | DR 환경엔 Redis 없음 (선택적 복구, ADR-0004) |
| PK는 `IDENTITY` 대신 시퀀스 + 보정 가능 구조 또는 UUIDv7 검토 — 현재는 `IDENTITY` + Failover 시 `scripts/dr/fix-sequences.sql` 로 보정 | Failover 시 시퀀스 충돌 방지 |
