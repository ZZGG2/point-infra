# Architecture Decision Records

기술 선택마다 **맥락 → 결정 → 대안 비교 → 결과(트레이드오프)** 를 남긴다. 면접에서 "왜?"에 답하는 1차 자료.

| # | 제목 | 상태 |
|---|---|---|
| [0001](0001-modular-monolith-with-selective-msa.md) | 모듈러 모놀리스 + 선택적 MSA | Accepted |
| [0002](0002-eks-karpenter-over-lambda-asg.md) | 이벤트 확장에 EKS + Karpenter 채택 (Lambda, EC2 ASG 기각) | Accepted |
| [0003](0003-multicloud-pilot-light-dr.md) | 멀티클라우드 Pilot Light DR (GCP) | Accepted |
| [0004](0004-selective-recovery.md) | DR 시 선택적 복구 (모놀리스만) | Accepted |
| [0005](0005-cdc-debezium-replication.md) | Debezium CDC 기반 비동기 복제 | Superseded by ADR-0020 |
| [0006](0006-aurora-postgresql.md) | Aurora PostgreSQL 채택 | Superseded by ADR-0013 |
| [0007](0007-redis-queue-and-dedup.md) | Redis 기반 대기열·중복 방지 | Accepted |
| [0008](0008-kafka-async-ledger-sync.md) | Kafka 비동기 원장 반영 | Superseded by ADR-0019 |
| [0009](0009-terraform-gitops-split.md) | Terraform(인프라) / ArgoCD(워크로드) 역할 분리 | Accepted |
| [0010](0010-dr-independence.md) | DR 경로의 AWS 비의존성 (State, 이미지, ArgoCD) | Accepted |
| [0011](0011-manual-failover-approval.md) | 자동 Failover 대신 승인 기반 Failover | Accepted |
| [0012](0012-polyrepo-split.md) | 레포지토리 분리 (infra / backend / frontend) | Accepted |
| [0013](0013-rds-postgresql.md) | Main DB 로 RDS for PostgreSQL 채택 | Accepted |
| [0014](0014-gateway-api.md) | 트래픽 진입에 Gateway API 채택 | Accepted |
| [0015](0015-web-pod-frontend.md) | 프론트엔드를 web 파드로 서빙 | Accepted |
| [0016](0016-dr-dns-failover.md) | DR DNS 전환을 AWS 컨트롤 플레인 없이 수행 | Proposed |
| [0017](0017-quiz-batch-settlement.md) | 퀴즈 이벤트 보상을 이벤트 종료 후 일괄 정산 | Accepted |
| [0018](0018-quiz-immediate-reward.md) | 퀴즈 당첨 보상을 다시 즉시 지급 (ADR-0017 철회) | Proposed |
| [0019](0019-redis-stream-ledger-sync.md) | 원장 반영 경로를 Kafka 에서 Redis Stream 으로 변경 (ADR-0008 대체) | Accepted |
| [0020](0020-postgresql-logical-replication.md) | DR 복제를 PostgreSQL 네이티브 논리 복제로 변경 (ADR-0005 대체) | Accepted |
| [0021](0021-spring-boot-4-upgrade.md) | Spring Boot 3.5 → 4.1 업그레이드 | Accepted |

## 템플릿
```markdown
# ADR-XXXX: 제목
- 상태: Proposed | Accepted | Superseded by ADR-YYYY
- 날짜: YYYY-MM-DD
## 맥락
## 결정
## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
## 결과 (긍정 / 부정 / 후속 과제)
```
