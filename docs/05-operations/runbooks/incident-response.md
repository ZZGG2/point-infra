# Runbook: 장애 대응

## 1. 심각도

| 등급 | 정의 | 예시 | 목표 대응 |
|---|---|---|---|
| P1 | 핵심 기능 전체 불가 / 데이터 위험 | 로그인 불가, 리전 장애, CDC 정지 장기화 | 5분 내 인지, 즉시 대응 |
| P2 | 일부 기능 저하 | 이벤트 지연, 원장 반영 지연 | 30분 |
| P3 | 영향 미미 | VPN 터널 1개 Down | 업무 시간 |

## 2. 진단 흐름

```
알람 수신
 ├─ 단일 AZ 문제? → Multi-AZ 자동 복구 대기 + 관찰
 ├─ 특정 서비스 문제? → 최근 배포 확인 → ArgoCD Rollback
 ├─ 데이터 계층 문제? → Aurora Failover 상태 / Redis / MSK 확인
 └─ 리전/사업자 수준 문제?
      ├─ AWS Health Dashboard 확인
      ├─ 15분 이상 지속 예상 또는 복구 시점 불명
      └─ → 장애 선언 → [DR Runbook](../../06-disaster-recovery/dr-runbook.md)
```

## 3. 공통 조치
| 상황 | 조치 |
|---|---|
| 잘못된 배포 | Git revert → ArgoCD 자동 동기화 (또는 ArgoCD UI Rollback) |
| 노드 부족 | Karpenter 로그, Spot 용량 오류 시 NodePool에 On-Demand 허용 |
| DB 커넥션 고갈 | HikariCP 설정, RDS Proxy 도입 검토 |
| Kafka lag 폭증 | point consumer 레플리카 확장 (파티션 수 상한 유의) |

## 4. 사후 (Postmortem)
- 템플릿: 타임라인 / 영향 / 근본 원인 / 잘된 점 / 개선 과제 (Blameless)
