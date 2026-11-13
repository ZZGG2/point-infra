# DR Runbook — Failover / Failback

> 원칙: **승인 1회 이후 사람이 콘솔에서 하는 작업은 0개.** 모든 단계는 `.github/workflows/dr-failover.yml` 이 수행하고, 이 문서는 각 단계의 의미와 실패 시 수동 대응을 기록한다.

## 0. 전제 조건 (평시 점검 — 월 1회)
- [ ] CDC Lag p99 ≤ 5초
- [ ] Artifact Registry에 최신 monolith 이미지 존재 (ECR과 태그 일치)
- [ ] GCP Secret Manager 시크릿 최신화
- [ ] `gcp-dr-compute` plan 성공 (GCS state 접근 확인)
- [ ] Route 53 Secondary 레코드 = GCP Static IP
- [ ] 온콜·승인자 연락망 최신

## 1. 장애 선언 기준
아래 **모두** 충족 시 DR 가동을 승인한다.
1. Route 53 Health Check 실패 ≥ 3분 지속
2. AWS Health Dashboard에서 리전/서비스 장애 확인 또는 원인 불명
3. 15분 내 복구 가능성이 낮다고 판단

## 2. Failover 절차

| # | 단계 | 실행 | 검증 | 실패 시 |
|---|---|---|---|---|
| 1 | 워크플로 실행 | `dr-failover.yml` (workflow_dispatch, reason 입력) | 승인 요청 도착 | - |
| 2 | 승인 | `dr-production` 환경 Reviewer | 승인 기록 | - |
| 3 | 복제 종료 확인 | 마지막 heartbeat 시각 기록 → **실제 RPO 기록** | `dr_heartbeat` 조회 | 기록만 하고 진행 |
| 4 | Cloud SQL 승격 | `scripts/dr/promote-cloudsql.sh` (sink 계정 NOLOGIN, app_rw LOGIN, 시퀀스 보정) | app_rw 접속 성공 | psql 수동 실행 |
| 5 | 컴퓨팅 생성 | `terraform apply envs/gcp-dr-compute` | GKE RUNNING | 재시도 1회 → 존(zone) 변경 변수 |
| 6 | GitOps 부트스트랩 | Terraform helm_release (ArgoCD + root-gcp-dr) | ArgoCD Apps Healthy | `kubectl apply -k k8s/argocd` |
| 7 | 앱 기동 | ArgoCD 자동 동기화 (monolith, maintenance) | readiness OK | 이미지 태그/시크릿 확인 |
| 8 | 트래픽 전환 | `scripts/dr/switch-dns.sh to-gcp` | `dig` 결과 GCP IP | Route 53 장애 시 NS 변경 절차 |
| 9 | 스모크 테스트 | 로그인 → 잔액 조회 → 내역 조회 | 200 OK | 롤백 판단 |
| 10 | 공지 | 이벤트 점검 공지, 상태 페이지 | - | - |

**완료 시 기록:** 승인 시각, 각 단계 소요 시간, 최종 RTO, 실제 RPO → `dr-drill-plan.md` 결과 표

## 3. Failback 절차 (계획된 점검)

| # | 단계 | 비고 |
|---|---|---|
| 1 | AWS 정상화 확인, `aws-main` plan 무변경 확인 | |
| 2 | Aurora를 Cloud SQL 최신 상태로 동기화 | 방법 A: 역방향 CDC (Cloud SQL → Aurora) / 방법 B: 점검 중 덤프·복원 |
| 3 | 점검 시작 — GCP 쓰기 중단 (maintenance 모드) | 쓰기 동결 |
| 4 | 최종 동기화 + 행 수/체크섬 검증 | |
| 5 | DNS를 AWS로 전환 | |
| 6 | Kafka consumer 재개 → 미반영 reward 처리 (멱등) | |
| 7 | 정방향 CDC 재구성 (Debezium slot 재생성, 초기 스냅샷) | |
| 8 | `terraform destroy envs/gcp-dr-compute` | 비용 원복 |
| 9 | Postmortem 작성 | |
