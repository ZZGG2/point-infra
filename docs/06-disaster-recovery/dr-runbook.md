# DR Runbook — Failover / Failback

> 원칙: **승인 1회 이후 사람이 콘솔에서 하는 작업은 0개.** 모든 단계는 `.github/workflows/dr-failover.yml` 이 수행하고, 이 문서는 각 단계의 의미와 실패 시 수동 대응을 기록한다.

## 0. 전제 조건 (평시 점검 — 월 1회)
- [ ] 복제 Lag p99 ≤ 5초, RDS slot `dr_subscription` 활성·`OldestReplicationSlotLag` 정상
- [ ] Artifact Registry에 최신 core-service 이미지 존재 (ECR과 태그 일치)
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
| 7 | Cloud SQL 승격 | 클러스터 내부 Job: `promote-cloudsql.sh promote` → 구독 해제(`DISABLE` → `SET (slot_name = NONE)` → `DROP SUBSCRIPTION`), app_rw LOGIN, `fix-sequences.sql`, `reconcile-wallet.sql` | app_rw 접속 성공, drift 건수 기록 | 같은 SQL 을 `kubectl run` 으로 수동 실행 |
| 8 | 앱 기동 | ArgoCD 자동 동기화 (core-service, maintenance) | readiness OK | 이미지 태그/시크릿 확인 |
| 9 | 트래픽 전환 | `scripts/dr/switch-dns.sh to-gcp` | `dig` 결과 GCP IP | §4 DNS 전환 시나리오 |
| 10 | 스모크 테스트 | `smoke-test.sh` (`DR_BASE_URL` = GitHub Variables) — 로그인 → 잔액 조회 → 내역 조회 | 200 OK | 롤백 판단 |
| 11 | 공지 | 이벤트 점검 공지, 상태 페이지. **"이벤트 보상은 서비스 정상화 후 지급"** (미반영 당첨은 Failback 6단계에서 반영, ADR-0018) | - | - |

> **왜 이 순서인가:** Cloud SQL 은 Private IP(`10.30.0.0/20`) 전용이라 GitHub-hosted runner 에서는 `psql` 로 접속할 수 없다. runner 는 GCP API(gcloud, Terraform)만 쓰고, SQL 이 필요한 6·7단계는 GKE 생성 직후 클러스터 내부(같은 VPC)의 일회성 Pod/Job 으로 실행한다. core-service 는 7단계(app_rw LOGIN) 전까지 readiness 실패 상태로 대기한다.
>
> **RPO 기록 주의:** 장애 후 `now() - ts` 는 "장애 발생 후 경과 시간" 이지 RPO 가 아니다. 복제 지연(`replication_lag`)은 평시·드릴 지표로만 쓰고, 실제 RPO = (Main 중단 시각, AWS 기록으로 사후 확정) − `last_replicated_at`.
>
> **구독 해제 순서:** AWS 가 응답하지 않을 때 바로 `DROP SUBSCRIPTION` 하면 RDS 의 slot 을 지우려다 멈춘다. 드릴(클론)에서는 반대로 RDS 가 살아 있어 **원본 구독이 쓰는 slot 을 지워 평시 복제가 끊긴다.** 그래서 항상 `slot_name = NONE` 으로 연결을 먼저 끊는다 (ADR-0020).
>
> **지갑 잔액 보정:** 논리 복제는 트랜잭션 단위로 적용하므로 원장과 지갑이 어긋나지 않는 것이 정상이다. `reconcile-wallet.sql` 은 안전장치로 유지하고, drift 가 나오면 불일치 내역을 Failback 대사 자료로 남긴다 (드릴에서 drift 0 이 반복 확인되면 재검토).

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
| 1 | AWS 정상화 확인, `aws-main` plan 무변경 확인 | ⚠️ AWS 가 살아나도 **AWS core-service 는 0 으로 축소(또는 원장 consumer 비활성 — `REWARD_STREAM_ENABLED=false`)한 채 유지** — DR 기간 쓰기가 없는 RDS 에 consumer 가 먼저 지급하면 동기화와 충돌한다 (ADR-0018). RDS 에 남은 slot `dr_subscription` 을 지운다 (그대로 두면 WAL 이 계속 쌓인다, ADR-0020) |
| 2 | RDS를 Cloud SQL 최신 상태로 동기화 | 방법 A: 역방향 논리 복제 (Cloud SQL PUBLICATION → RDS SUBSCRIPTION) / 방법 B: 점검 중 덤프·복원. ⚠️ RDS 에만 커밋된 행(복제 지연분)이 있으면 방법 A 는 고유키 충돌로 apply 가 멈춘다 → 구독 전에 미복제 행을 따로 빼 둔다 (원장은 `idempotency_key` 기준). 다시 지급하는 건 6-1 되감기로 처리 (ADR-0020) |
| 3 | 점검 시작 — GCP 쓰기 중단 (maintenance 모드) | 쓰기 동결 |
| 4 | 최종 동기화 + 행 수/체크섬 검증 | |
| 5 | DNS를 AWS로 전환 | |
| 6-1 | consumer group `point-ledger` 위치 되감기 (consumer 정지 상태에서) | 보상 Stream 마다 `XGROUP SETID <stream> point-ledger <last_replicated_at − 여유(ms), Failover 6단계 기록값>-0` (대상: `reward:streams` 에 등록된 퀴즈 Stream + 해당 기간 `attendance:{yyyyMMdd}:rewards`). Stream ID 가 밀리초 타임스탬프라 시각으로 되감을 수 있다. RDS 에만 있던 지급이 2단계 동기화로 지워졌어도 다시 채워진다. 이미 있는 건은 멱등키로 무시 (ADR-0019) |
| 6-2 | Stream consumer 재개 (AWS core-service 스케일 원복) → 미반영 reward 처리 (멱등) | 퀴즈 당첨도 즉시 지급 (ADR-0018) — DR 중 일부만 지급된 이벤트가 여기서 채워진다. pending 0 까지 대기 |
| 6-3 | DLQ(`reward:dlq` Stream) 확인·재처리 | |
| 6-4 | 대사: 이벤트별 Redis 당첨자 Set ↔ 원장(`source=EVENT, reference_id=eventId`) | 차이 = 누락 → Stream 에 재등록. Set 과 Stream 이 같은 ElastiCache 에 있어 Redis 소실 시 복원 불가 (ADR-0019). 대사 배치 미구현 (ADR-0018 후속) → 수동 쿼리 |
| 6-5 | 장애 시점에 열려 있던 이벤트를 닫은 뒤 event-service 재개 | Failback 후 새 참여 방지 |
| 7 | 정방향 복제 재구성 | 역방향 구독(RDS)·발행(Cloud SQL) 제거 → Cloud SQL 대상 테이블을 비운 뒤 `cdc/subscription.sql` 로 재구독 (초기 복사, RDS 에 slot 재생성) |
| 8 | `terraform destroy envs/gcp-dr-compute` | 비용 원복 |
| 9 | Postmortem 작성 | |

> **지급 원칙 (ADR-0018):** DB 에 반영된 지급은 유지하고, 반영되지 않은 지급만 AWS Redis Stream 에 남은 항목으로 반영한다. 경계 조건 세 가지 — ① RDS 에만 커밋된 원장(복제 지연)은 Stream 에서 이미 `XACK` 돼 2단계 동기화로 지워지면 다시 오지 않는다 → 6-1 위치 되감기 ② DR 기간이 Stream 보존 기간(7일, `XTRIM MINID`)을 넘기면 항목이 정리된다 → 정리 작업을 멈추거나 만료 전 백업 ③ ElastiCache 까지 소실되면 미반영 명단은 복원할 수 없다 (ADR-0019).
