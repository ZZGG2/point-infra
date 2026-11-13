# 하이브리드 아키텍처: 모듈러 모놀리스 + 선택적 MSA

## 1. 왜 전체 MSA가 아닌가

| 관점 | 전체 MSA | 모듈러 모놀리스 + 선택적 MSA |
|---|---|---|
| 네트워크 지연 | 서비스 간 호출마다 홉 추가 | 대부분 in-process 호출 |
| 분산 트랜잭션 | Saga/보상 트랜잭션 다수 필요 | 원장은 단일 DB 트랜잭션 |
| 운영 비용 | 서비스 수 × (배포, 모니터링, 온콜) | 서비스 2개 |
| 확장 효율 | 도메인별 독립 확장 | 폭주 도메인만 독립 확장 (실제 필요한 부분) |
| 팀 규모 적합성 | 다수 팀 | 소규모 팀 / 1인 |

**결론:** 트래픽 패턴이 이질적인 도메인(event)만 분리하면 MSA 이점의 대부분을 얻고 비용의 대부분을 피할 수 있다.

## 2. 분리 기준 (Decision Criteria)

어떤 도메인을 MSA로 뺄지 판단하는 기준:

| 기준 | 질문 | event | point | user |
|---|---|---|---|---|
| 트래픽 이질성 | 다른 도메인과 피크 패턴이 다른가? | ✅ | ❌ | ❌ |
| 확장 독립성 | 이 도메인만 크게 확장해야 하나? | ✅ | ❌ | ❌ |
| 장애 격리 | 이 도메인 장애가 전체로 번지면 안 되나? | ✅ | - | - |
| 데이터 결합도 | 다른 도메인과 트랜잭션을 공유하나? | 낮음 | 높음 | 중간 |
| DR 필요성 | 리전 장애 시 반드시 살아야 하나? | ❌ | ✅ | ✅ |

## 3. 모놀리스 내부 모듈 경계

```
com.pointplatform.monolith
├── user/      (api, application, domain, infra)
├── asset/
├── point/     ← Kafka consumer 포함 (reward 반영)
├── cs/
└── common/    (보안, 예외, 공통 응답)
```

규칙:
- 모듈 간 호출은 `application` 계층의 public 인터페이스로만 한다.
- 다른 모듈의 `domain`, `infra` 패키지를 직접 import하지 않는다 (ArchUnit 테스트로 강제).
- 모듈별로 테이블을 소유하고 다른 모듈 테이블을 조인하지 않는다.
→ 향후 point 모듈 분리가 필요해져도 경계가 이미 있어 비용이 낮다.

## 4. 통신 방식

| From → To | 방식 | 이유 |
|---|---|---|
| Client → monolith / event | 동기 HTTP (ALB 경로 라우팅) | 단순 |
| event → point(원장) | **비동기 Kafka** | 피크 트래픽을 원장 DB에 직접 전달하지 않음 (부하 평탄화) |
| event → user (인증) | JWT 자체 검증 (공개키) | 이벤트 피크 시 monolith 호출 없음 |

## 5. 정합성 보장

- **at-least-once 전달 + 멱등 소비** = 사실상 exactly-once 반영
  - Producer: `enable.idempotence=true`, `acks=all`
  - Consumer: `point_ledger.idempotency_key` UNIQUE, 중복 시 무시
- Redis 당첨 기록 ↔ 원장 반영 결과를 이벤트 종료 후 **대사(Reconciliation) 배치**로 비교

## 6. 향후 진화 경로

| 트리거 | 다음 단계 |
|---|---|
| point 모듈의 쓰기 TPS가 DB 한계 근접 | point 모듈 분리 + 원장 DB 분리 |
| 팀이 3개 이상으로 증가 | 도메인별 서비스 소유권 분리 |
| 서비스 간 호출 증가 | Service Mesh(Istio/Linkerd) 검토 |
