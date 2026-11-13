# ADR-0008: Kafka 비동기 원장 반영
- 상태: Accepted · 날짜: 2026-11-05

## 결정
event-service는 당첨 결과를 **Kafka(MSK)** 로 발행하고, monolith point 모듈이 소비해 원장에 반영한다.

## 고려한 대안
| 대안 | 기각 이유 |
|---|---|
| event → monolith 동기 REST 호출 | 피크 트래픽이 그대로 monolith·DB로 전파 (격리 실패) |
| event가 DB에 직접 쓰기 | 서비스 간 DB 공유 = MSA 경계 붕괴 |
| SQS | GCP 이식성 낮음, CDC 파이프라인과 인프라 이원화 |
| **Kafka (MSK)** | 부하 평탄화(버퍼), 재처리, CDC와 인프라 공유 → **채택** |

## 비용 대안
- MSK Provisioned가 부담되면 **MSK Serverless** 또는 **EKS 위 Strimzi**로 대체 (단, MSK Connect는 MSK 전용 → Strimzi 시 Kafka Connect 직접 운영)
