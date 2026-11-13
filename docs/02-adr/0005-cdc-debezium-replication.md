# ADR-0005: Debezium CDC 기반 비동기 복제
- 상태: Accepted · 날짜: 2026-11-05

## 맥락
Aurora(AWS) → Cloud SQL(GCP)로 핵심 테이블을 실시간 복제해야 한다. 클라우드 관리형 복제는 클라우드 경계를 넘지 못한다.

## 결정
**Debezium PostgreSQL Source + Debezium JDBC Sink** 를 **MSK Connect**에서 운영하고, 전송은 HA VPN으로 한다. 복제 대상은 Publication으로 핵심 테이블만 지정한다.

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| 동기 복제 (2PC 등) | RPO 0 | 모든 커밋에 클라우드 간 RTT 추가, 한쪽 장애 시 쓰기 중단 | 가용성·성능 희생 |
| 주기적 덤프/복원 | 단순 | RPO = 덤프 주기 (수 시간) | 금융 요구 미달 |
| GCP Database Migration Service | 관리형, 지속 복제 지원 | 마이그레이션 목적 도구, 테이블 선택·장기 운영 유연성 제한 | 대안으로 문서화 (Plan B) |
| PostgreSQL 네이티브 논리 복제 | 추가 구성요소 없음 | 구독 측이 원천에 직접 접속, 모니터링/재처리 수단 약함 | 관측성 |
| **Debezium + Kafka** | 테이블 선택, 재처리(오프셋), 이미 MSK 보유, 표준 OSS | 운영 요소 증가, DDL 미복제 | **채택** |

## 결과
- RPO는 0이 아닌 **near-zero (목표 p99 ≤ 5초)** 로 정의하고 실측한다.
- 면접 표현: "RPO 0" ❌ → "비동기 CDC로 RPO 수 초 이내, 동기 복제는 성능·가용성 트레이드오프로 배제" ✅
- 후속: DDL 이중 적용(Flyway), 시퀀스 보정 스크립트, Slot Lag 알람
