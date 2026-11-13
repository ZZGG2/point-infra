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
| 3 | Cloud SQL 준비 | runner: `promote-cloudsql.sh prepare` (gcloud API — 드릴이면 클론 생성) | 인스턴스 RUNNABLE | `gcloud sql` 수동 실행 |
| 4 | 컴퓨팅 생성 | `terraform apply envs/gcp-dr-compute` | GKE RUNNING | 재시도 1회 → 존(zone) 변경 변수 |
| 5 | GitOps 부트스트랩 | Terraform helm_release (ArgoCD + root-gcp-dr) | ArgoCD Apps Healthy | `kubectl apply -k k8s/argocd` |
| 6 | 복제 종료 확인 · RPO 근거 기록 | 클러스터 내부 Pod: `record-rpo.sh` → `last_replicated_at`(heartbeat `ts`), `last_ledger_at`(`max(point_ledger.created_at)`) | 값 기록 | 기록만 하고 진행 |
| 7 | Cloud SQL 승격 | 클러스터 내부 Job: `promote-cloudsql.sh promote` → sink_writer NOLOGIN, app_rw LOGIN, `fix-sequences.sql`, `reconcile-wallet.sql` | app_rw 접속 성공, drift 건수 기록 | 같은 SQL 을 `kubectl run` 으로 수동 실행 |
| 8 | 앱 기동 | ArgoCD 자동 동기화 (monolith, maintenance) | readiness OK | 이미지 태그/시크릿 확인 |
| 9 | 트래픽 전환 | `scripts/dr/switch-dns.sh to-gcp` | `dig` 결과 GCP IP | §4 DNS 전환 시나리오 |
| 10 | 스모크 테스트 | `smoke-test.sh` (`DR_BASE_URL` = GitHub Variables) — 로그인 → 잔액 조회 → 내역 조회 | 200 OK | 롤백 판단 |
| 11 | 공지 | 이벤트 점검 공지, 상태 페이지 | - | - |

> **왜 이 순서인가:** Cloud SQL 은 Private IP(`10.30.0.0/20`) 전용이라 GitHub-hosted runner 에서는 `psql` 로 접속할 수 없다. runner 는 GCP API(gcloud, Terraform)만 쓰고, SQL 이 필요한 6·7단계는 GKE 생성 직후 클러스터 내부(같은 VPC)의 일회성 Pod/Job 으로 실행한다. monolith 는 7단계(app_rw LOGIN) 전까지 readiness 실패 상태로 대기한다.
>
> **RPO 기록 주의:** 장애 후 `now() - ts` 는 "장애 발생 후 경과 시간" 이지 RPO 가 아니다. 복제 지연(`replication_lag`)은 평시·드릴 지표로만 쓰고, 실제 RPO = (Main 중단 시각, AWS 기록으로 사후 확정) − `last_replicated_at`.
>
> **지갑 잔액 보정:** JDBC Sink 는 테이블별 토픽을 병렬 소비하므로 원장과 지갑이 서로 다른 시점에서 끊길 수 있다. 원장(append-only)을 기준으로 지갑을 맞추고 불일치 내역은 Failback 대사 자료로 남긴다 (`reconcile-wallet.sql`).

**완료 시 기록:** 승인 시각, 각 단계 소요 시간, 최종 RTO, 실제 RPO → `dr-drill-plan.md` 결과 표

## 4. DNS 전환 시나리오 (ADR-0016, Proposed)

| 장애 범위 | 전환 방법 | 비고 |
|---|---|---|
| (A) AWS 서울 리전(`ap-northeast-2`) 단일 리전 장애 | Route 53 Failover 레코드. Health Check 는 글로벌 데이터 플레인에서 동작하므로 리전 장애에도 판정·응답은 유지된다. 승인 기반(ADR-0011) 전환은 Primary Health Check 를 Invert 하거나, GCP 쪽에 둔 "전환 플래그" 엔드포인트를 Health Check 대상으로 삼아 GCP 에서 플래그를 바꾼다 | TTL 60s, 약 1~2분 |
| (B) AWS 글로벌 컨트롤 플레인(Route 53 API, IAM) 장애 | Route 53 API 를 호출하지 않는 방식이어야 한다: ① 위 "GCP 전환 플래그" Health Check (데이터 플레인만 사용), ② AWS 외부의 독립 권한 DNS(예: Cloudflare)를 앞단에 두거나 Route 53 과 Secondary DNS 를 병행 | 방식 확정은 ADR-0016 |
| ✗ 도메인 등록기관에서 NS 변경 | 사용하지 않는다 | TLD 의 NS TTL(보통 24~48시간) 때문에 RTO 30분 달성 불가 |

- `switch-dns.sh` 의 `aws route53 update-health-check` 는 AWS 자격 증명과 Route 53 컨트롤 플레인이 필요해 ADR-0010 과 충돌한다 → ADR-0016 결정 후 교체.

## 5. Failback 절차 (계획된 점검)

| # | 단계 | 비고 |
|---|---|---|
| 1 | AWS 정상화 확인, `aws-main` plan 무변경 확인 | |
| 2 | RDS를 Cloud SQL 최신 상태로 동기화 | 방법 A: 역방향 CDC (Cloud SQL → RDS) / 방법 B: 점검 중 덤프·복원 |
| 3 | 점검 시작 — GCP 쓰기 중단 (maintenance 모드) | 쓰기 동결 |
| 4 | 최종 동기화 + 행 수/체크섬 검증 | |
| 5 | DNS를 AWS로 전환 | |
| 6 | Kafka consumer 재개 → 미반영 reward 처리 (멱등) | |
| 7 | 정방향 CDC 재구성 (Debezium slot 재생성, 초기 스냅샷) | |
| 8 | `terraform destroy envs/gcp-dr-compute` | 비용 원복 |
| 9 | Postmortem 작성 | |
