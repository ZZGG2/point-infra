# KEDA
Helm chart `kedacore/keda` 를 ArgoCD Application 으로 설치.
- event-service: Cron + CPU (base/event-service/scaledobject.yaml)
- core-service point consumer: Redis Stream 트리거 (TODO) — `redis-streams` scaler 로 consumer group `point-ledger` 의 pending 수 기준. 퀴즈 Stream 이 이벤트별(`event:{id}:rewards`)이라 고정 이름 트리거를 어떻게 걸지는 미정 (ADR-0019)
