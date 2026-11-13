# 개발 가이드

## 1. 기술 스택

| 영역 | 선택 | 버전 (고정) |
|---|---|---|
| 언어 / 런타임 | Java (Temurin) | 21 LTS |
| 프레임워크 | Spring Boot | 3.x |
| 빌드 | Gradle | 8.x |
| DB 마이그레이션 | Flyway | - |
| 테스트 | JUnit 5, Testcontainers, ArchUnit | - |
| 컨테이너 | Docker (multi-stage, distroless/temurin-jre) | - |
| 로컬 인프라 | Docker Compose (PostgreSQL 16, Redis 7, Kafka KRaft) | - |
| 부하 테스트 | k6 | - |
| 프론트엔드 | React 18 + Vite + TypeScript (strict), TanStack Query, openapi-typescript | Node 20 LTS |

## 2. 로컬 개발 환경 (point-backend 레포)

```bash
make local-up           # docker compose up -d
make run-monolith       # http://localhost:8080
make run-event          # http://localhost:8081
make local-down
```

| 서비스 | 포트 |
|---|---|
| monolith | 8080 |
| event-service | 8081 |
| PostgreSQL | 5432 |
| Redis | 6379 |
| Kafka | 9092 |
| Kafka UI | 8090 |

## 3. 브랜치 · 커밋 · PR 규칙

팀 공통 규칙 문서로 일원화: [docs/team/github-workflow.md](../team/github-workflow.md)

## 4. 레포 구성

| 레포 | 내용 |
|---|---|
| point-infra | 인프라, GitOps, 문서 (이 레포) |
| point-backend | monolith, event-service, OpenAPI |
| point-frontend | React + Vite + TypeScript SPA |

## 5. 코드 규칙

- 모듈 경계: [hybrid-msa.md §3](../01-architecture/hybrid-msa.md) — ArchUnit 테스트로 강제
- 설정: 환경별 값은 `application-{profile}.yml` 이 아니라 **환경 변수 / K8s ConfigMap·Secret** 으로 주입 (12-Factor)
- 프로필: `local`, `aws`, `gcp-dr`
- 헬스체크: `/actuator/health/liveness`, `/actuator/health/readiness` 분리
- Graceful Shutdown: `server.shutdown=graceful`, preStop sleep 10s (ALB 등록 해제 대기)

## 6. DR 모드 고려 코딩 규칙

| 규칙 | 이유 |
|---|---|
| 클라우드 SDK 직접 호출 금지 (S3 등은 추상화 인터페이스 뒤로) | GCP에서도 같은 이미지가 동작해야 함 |
| Kafka 미연결 시에도 monolith 기동 가능 (`spring.kafka.listener.auto-startup` 프로필별 제어) | DR 환경엔 Kafka 없음 |
| PK는 `IDENTITY` 대신 시퀀스 + 보정 가능 구조 또는 UUIDv7 검토 | Failover 시 시퀀스 충돌 방지 |
