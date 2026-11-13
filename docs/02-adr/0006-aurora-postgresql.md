# ADR-0006: Aurora PostgreSQL 채택
- 상태: Accepted · 날짜: 2026-11-05

## 결정
Main DB는 **Aurora PostgreSQL**, DR DB는 **Cloud SQL for PostgreSQL**.

## 이유
| 기준 | PostgreSQL | MySQL |
|---|---|---|
| 양 클라우드 관리형 지원 | ✅ Aurora / Cloud SQL | ✅ Aurora / Cloud SQL |
| Debezium 논리 복제 | pgoutput 내장, Publication으로 테이블 선택 | binlog 기반, 가능 |
| 원장 모델 적합성 (제약조건, 트랜잭션) | 우수 | 양호 |
| 동일 엔진 양쪽 사용 → DR 시 SQL 호환 | ✅ | ✅ |

- Aurora vs RDS: 스토리지 자동 확장, 빠른 장애조치, 읽기 복제본 확장. 데모 비용이 부담되면 **RDS PostgreSQL Multi-AZ**로 대체 가능 (설계 동일).
- 두 클라우드 모두 **같은 메이저 버전**으로 고정한다.
