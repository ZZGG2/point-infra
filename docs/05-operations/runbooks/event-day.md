# Runbook: 이벤트 당일 운영

## D-1
- [ ] 이벤트 생성 (당첨 수량·지급 포인트·마감 시각) — 생성하는 순간 참여가 열린다 → **시작 시각에 실행**하거나, 시작 전 공지 화면에서 참여를 막는다
  ```bash
  # ADMIN_API_TOKEN 은 Secrets Manager 의 event-secrets 에서 꺼낸다 (명령 기록·로그에 평문을 남기지 않는다)
  curl -sS -X POST "https://<도메인>/api/events/admin/<eventId>" \
    -H "X-Admin-Token: $ADMIN_API_TOKEN" -H "Content-Type: application/json" \
    -d '{"stock": 100, "amount": 500, "endsAt": "2026-12-01T21:00:00+09:00"}'
  ```
  - 201 이면 `GET /api/events/<eventId>/status` 로 `open=true`·재고·금액·`endsAt` 확인
  - 409 = 이미 쓴 id → **새 id** 로 다시 만든다 (같은 id 재사용 불가). 403 = 토큰 불일치 또는 미설정
  - 시작 시각 예약 생성(Job)은 아직 없다 ([api-spec](../../03-development/api-spec.md#event-service))
- [ ] KEDA ScaledObject Cron 시간 확인 (시작 5분 전 ~ 종료 30분 후)
- [ ] ArgoCD Sync Window: 이벤트 시간대 배포 차단 확인
- [ ] Spot 용량 리스크 대비: NodePool에 On-Demand fallback 허용 확인
- [ ] 서브넷 가용 IP 확인 (피크 노드 수 × 노드당 파드)
- [ ] WAF Rate Limit 임계값 검토

## T-10분
- [ ] Grafana Business / Scaling 대시보드 열기
- [ ] DLQ(`reward:dlq`) = 0, 보상 Stream pending ≈ 0 확인

## T-5분 (자동)
- [ ] KEDA가 event-service 목표 레플리카로 확장했는지 확인
- [ ] Karpenter 노드 Ready, Pending 파드 0

## T+0 ~ 종료
| 관찰 지표 | 정상 | 조치 |
|---|---|---|
| event p95 | < 500ms | 초과 시 HPA 상한/노드 확인 |
| 5xx | < 0.1% | 급증 시 incident-response |
| 보상 Stream pending | 감소 추세 | 증가만 하면 point consumer 확장 |
| Redis CPU | < 70% | 초과 시 읽기 경로 점검 |

## 종료 후
- [ ] 보상 Stream pending = 0 확인 (퀴즈 당첨은 즉시 지급 — ADR-0018, 별도 정산 없음)
- [ ] 대사 배치 실행 (퀴즈: Redis 당첨자 Set ↔ ledger, 출석: Redis 비트맵 ↔ ledger) — *배치 미구현* ([domain-model §4](../../03-development/domain-model.md))
- [ ] DLQ 처리
- [ ] 스케일 인/노드 회수 확인
- [ ] 이벤트 비용·지표 기록 → finops.md
