# CI/CD 파이프라인

## 1. 전체 흐름 (멀티 레포)

```
 point-backend                         point-infra (GitOps 원천)                 클러스터
 ─────────────                         ─────────────────────────                 ────────
 PR ─▶ CI: test·ArchUnit·build
 merge ─▶ 이미지 빌드 → Trivy
        → ECR + Artifact Registry 이중 푸시
        → point-infra 에 "태그 bump PR" 자동 생성 ─▶ PR 리뷰·머지 ─▶ ArgoCD(EKS) 동기화
                                                  (overlays/aws, overlays/gcp-dr)

 point-frontend
 ─────────────
 PR ─▶ CI: lint·typecheck·test·build
 merge ─▶ web 이미지 빌드(nginx) → ECR + Artifact Registry 이중 푸시
        → point-infra 에 "태그 bump PR" 자동 생성                (web 파드, Gateway 가 / 를 라우팅)

 point-infra
 ───────────
 PR(infra/**) ─▶ fmt·tflint·checkov·plan(코멘트) ─▶ merge ─▶ apply (environment 승인)
 manual ─▶ dr-failover.yml (dr-production 승인)
```

- **배포의 단일 창구는 point-infra.** 앱 레포는 이미지만 만들고, "무엇을 어디에 배포할지"는 항상 infra 레포 PR로 기록된다 → 감사 추적 + 롤백 = `git revert`.
- 태그 bump PR 생성: GitHub App(또는 Fine-grained PAT, infra 레포 contents/pull-requests 권한만) 사용.

## 2. 워크플로 목록

| 레포 | 파일 | 트리거 | 내용 |
|---|---|---|---|
| backend | `ci.yml` | PR, push main | Gradle test, ArchUnit, 이미지 빌드·스캔·이중 푸시, infra 태그 bump PR |
| frontend | `ci.yml` | PR, push main | lint, typecheck, test, web 이미지 빌드·이중 푸시, infra 태그 bump PR |
| infra | `terraform-plan.yml` | PR (infra/**) | fmt, validate, tflint, checkov, plan → PR 코멘트 |
| infra | `terraform-apply.yml` | push main (infra/**) | 환경별 apply, `environment` 승인 |
| infra | `drift-detect.yml` | 주 1회 cron | 모든 env plan → 변경 감지 시 이슈 생성 |
| infra | `dr-failover.yml` | workflow_dispatch | DR 전환 (승인 필수) |
| infra | `dr-failback.yml` | workflow_dispatch | AWS 복귀 |

## 3. 인증 (Access Key 0개)

| 대상 | 방식 |
|---|---|
| AWS | GitHub OIDC → IAM Role (`sts:AssumeRoleWithWebIdentity`, repo/branch 조건) |
| GCP | GitHub OIDC → Workload Identity Federation → Service Account |

## 4. GitOps 구조

```
k8s/argocd/
├── aws/          # EKS root → monolith + event-service + platform, 이벤트 시간 Sync Window
└── gcp-dr/       # GKE root (Terraform argocd-bootstrap 이 등록) → monolith + maintenance
```
- AWS: `monolith`, `event-service`, `web` 생성 + Gateway(ALB)
- GCP-DR: `monolith`, `web` 생성 + `maintenance` (이벤트 경로 503) → **선택적 복구가 Git에 선언됨**

## 5. 배포 전략

| 서비스 | 전략 | 이유 |
|---|---|---|
| monolith | Rolling Update (maxUnavailable 0) | 단순, 무중단 |
| event-service | Rolling Update + **이벤트 시간대 배포 금지 (Sync Window)** | 피크 중 변경 리스크 제거 |
| (확장) | Argo Rollouts Canary | Phase 6 선택 과제 |
