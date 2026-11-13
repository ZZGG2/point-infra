# 로드맵 & WBS

> 기간 가정: 10주. 실제 일정에 맞게 주차만 조정.

## Phase 개요

| Phase | 기간 | 목표 | 완료 조건 (Definition of Done) |
|---|---|---|---|
| 0. 설계 | 1주 | 아키텍처·ADR·CIDR 확정 | 본 docs 리뷰 완료, CIDR 변경 없음 선언 |
| 1. 앱 MVP | 2주 | monolith + event-service 로컬 동작 | docker compose에서 S3/S4 시나리오 통과 |
| 2. AWS 기반 | 1.5주 | VPC, EKS, Aurora, Redis, MSK Terraform | `terraform apply` 1회로 재현 |
| 3. 플랫폼 | 1.5주 | ArgoCD, Karpenter, KEDA, ESO, 모니터링, CI/CD | main 머지 → 자동 배포, S2 부하 테스트 통과 |
| 4. DR 기반 | 1.5주 | GCP standby, HA VPN, CDC | CDC Lag 대시보드, p99 ≤ 5초 |
| 5. DR 자동화 | 1.5주 | gcp-dr-compute, dr-failover 워크플로 | 전체 훈련 1회, RTO ≤ 30분 |
| 6. 마무리 | 1주 | 비교 실험, 비용 분석, 문서·블로그 | README 결과 수치 채움, 회고 |

## 상세 WBS

### Phase 0 — 설계
- [ ] 아키텍처 다이어그램 (draw.io / Excalidraw) → `docs/images/`
- [ ] ADR 0001~0011 검토
- [ ] CIDR, 네이밍, 태깅 규칙 확정
- [ ] AWS/GCP 계정, 예산 알림 설정

### Phase 1 — 애플리케이션
- [ ] monolith: user(JWT), point(원장·멱등), asset(Mock), cs
- [ ] event-service: 출석(Bitmap), 퀴즈(Lua), 대기열(ZSET), Kafka 발행
- [ ] point consumer + DLQ
- [ ] Flyway 스키마, Testcontainers 통합 테스트, ArchUnit
- [ ] Dockerfile (multi-stage, non-root)

### Phase 2 — AWS 인프라
- [ ] bootstrap (S3 state)
- [ ] modules/aws/vpc, eks, aurora, elasticache, msk, ecr
- [ ] envs/aws-main 조립
- [ ] GitHub OIDC Role

### Phase 3 — 플랫폼 & CI/CD
- [ ] ArgoCD 설치, App of Apps
- [ ] Karpenter NodePool (core: OD / event: Spot)
- [ ] KEDA (Cron, Kafka lag)
- [ ] External Secrets, kube-prometheus-stack, Fluent Bit
- [ ] point-backend ci.yml (이미지 푸시 → 태그 bump PR), point-frontend ci.yml, terraform-plan/apply.yml
- [ ] edge: Route 53, CloudFront, WAF, ACM

### Phase 4 — DR 기반
- [ ] bootstrap/gcp (GCS state), Workload Identity Federation
- [ ] envs/gcp-dr-standby (VPC, PSA, Cloud SQL, Static IP, AR, Secret Manager)
- [ ] shared/vpn (HA VPN ↔ AWS VPN, BGP)
- [ ] Aurora 논리 복제 파라미터, Publication
- [ ] MSK Connect: Debezium source + JDBC sink
- [ ] heartbeat 기반 Lag 대시보드
- [ ] CI 이미지 이중 푸시

### Phase 5 — DR 자동화
- [ ] envs/gcp-dr-compute (GKE, argocd-bootstrap)
- [ ] k8s/overlays/gcp-dr, maintenance 응답
- [ ] scripts/dr/* (promote, fix-sequences, switch-dns)
- [ ] dr-failover.yml / dr-failback.yml
- [ ] 부분 훈련 → 전체 훈련 → 개선 → 재훈련

### Phase 6 — 마무리
- [ ] 비교 실험 3종 그래프
- [ ] FinOps 실측 표
- [ ] README 결과 섹션, 데모 영상(3분)
- [ ] Velog 시리즈 (설계 / 이벤트 확장 / DR 훈련 / 트러블슈팅)
