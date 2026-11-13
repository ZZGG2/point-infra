# ADR-0013: Main DB 로 RDS for PostgreSQL 채택
- 상태: Accepted · 날짜: 2026-11-13

## 맥락
원장(Source of Truth)은 PostgreSQL 16 이어야 하고(ADR-0006의 엔진 결정 유지), Debezium 논리 복제로 GCP Cloud SQL 에 복제된다(ADR-0005).
이벤트 폭주 시 쓰기는 Redis 판정 → Kafka → 원장 비동기 반영(ADR-0007, 0008)이라 DB 에 직접 몰리는 부하는 평탄화된다.

## 결정
AWS Main DB 는 **RDS for PostgreSQL 16 Multi-AZ** 로 운영한다.
- 파라미터: `rds.logical_replication=1`, `rds.force_ssl=1`
- 스토리지: gp3, KMS 암호화, `max_allocated_storage` 자동 확장
- 앱 계정 `app_rw` 는 ArgoCD Sync Job(`k8s/overlays/aws/db-init.yaml`)이 생성하고, 마스터 계정은 그 Job 에만 주입한다.
- 학습 환경은 `rds_multi_az = false`, `db.t4g.micro` 로 비용을 최소화한다 (변수로 전환).

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| Aurora PostgreSQL (Provisioned / Serverless v2) | 30초 내외 Failover, 스토리지 자동 확장, Serverless 용량 자동 조절 | 비용(I/O 포함), 학습 환경 고정비 | 쓰기 폭주를 Kafka 가 흡수해 Aurora 장점이 크게 드러나지 않음 |
| EKS 위 자체 운영 (CloudNativePG) | 클라우드 중립 | 백업·Failover·패치 운영 부담 | 원장 DB 를 직접 운영할 이유 없음 |

## 결과
- (+) 비용·구성 단순화, Debezium·Cloud SQL 과 동일 엔진 유지 → DR 설계 그대로
- (−) Multi-AZ Failover 1~2분 (리전 내 RTO). 읽기 확장이 필요해지면 Read Replica 추가
- 후속: 부하 테스트에서 커넥션·IOPS 한계 실측 후 인스턴스 클래스 결정
