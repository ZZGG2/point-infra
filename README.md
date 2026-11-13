# Point Platform — Hybrid MSA & Multi-Cloud Pilot Light DR

> 마이데이터 기반 자산조회 + 트래픽 폭주형 포인트 이벤트를 처리하는 **금융 포인트 플랫폼**의 클라우드 인프라 포트폴리오.
> 목표 직무: MSP(메가존클라우드, 베스핀글로벌 등) Cloud Engineer / Solutions Architect

[![Architecture](https://img.shields.io/badge/Main-AWS-orange)]() [![DR](https://img.shields.io/badge/DR-GCP%20Pilot%20Light-blue)]() [![IaC](https://img.shields.io/badge/IaC-Terraform-purple)]() [![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-green)]()

---

## 1. 한 줄 요약

**"평소엔 싸게, 이벤트 땐 초 단위로 크게, 리전이 죽어도 30분 안에 돈(포인트)은 지킨다."**

| 구분 | 전략 | 핵심 수치 (목표) |
|---|---|---|
| 애플리케이션 | 모듈러 모놀리스 + 폭주 도메인만 MSA | 이벤트 피크 평시 대비 100x+ 처리 |
| 확장 | EKS + Karpenter + HPA/KEDA (사전 스케일) | 노드 확장 60초 이내 |
| 재해복구 | AWS(Main) → GCP(Pilot Light) | **RTO ≤ 30분 / RPO ≤ 5초 (near-zero)** |
| 자동화 | Terraform(인프라) + ArgoCD(워크로드) | DR 전환 = 승인 1회 + 파이프라인 1회 |
| 비용 | DR 컴퓨팅 0, DB만 상시 복제 | 1:1 Active-Active 대비 DR 비용 대폭 절감 |

## 2. 아키텍처 개요

```
                          ┌──────────── Route 53 (Failover Routing + Health Check) ────────────┐
                          │ Primary                                                Secondary   │
                          ▼                                                                    ▼
  ┌──────────────── AWS ap-northeast-2 (Main, 100%) ────────────────┐   ┌──────── GCP asia-northeast3 (DR) ────────┐
  │ WAF → ALB (Gateway API)                                          │   │ [상시] VPC, Cloud SQL(복제 대상),          │
  │   ├─ /api/**         → Monolith (user/asset/point/cs)  On-Demand │   │        Static IP, Secret Manager,          │
  │   ├─ /api/events/**  → event-service (MSA)       Karpenter Spot  │   │        Artifact Registry                    │
  │   └─ /**             → web (SPA)                                 │   │ [장애 시 생성] GKE + ArgoCD               │
  │                         │ Redis(대기열/중복방지)                    │   │        → Monolith + web 배포               │
  │                         └─ Kafka(MSK) ──▶ Monolith point 모듈     │   │        → /api/events/** = 점검 페이지       │
  │ RDS PostgreSQL ──(Debezium CDC / MSK Connect)──── HA VPN ────────┼──▶│                                            │
  └──────────────────────────────────────────────────────────────────┘   └────────────────────────────────────────────┘
```

상세: [docs/01-architecture/architecture-overview.md](docs/01-architecture/architecture-overview.md)

## 3. 문서 지도 (Docs Map)

| 단계 | 문서 | 내용 |
|---|---|---|
| 개요 | [project-overview](docs/00-overview/project-overview.md) | 배경, 비즈니스 시나리오, 범위, 성공 지표 |
| | [requirements](docs/00-overview/requirements.md) | 기능/비기능 요구사항, 규제 고려사항 |
| 아키텍처 | [architecture-overview](docs/01-architecture/architecture-overview.md) | 전체 구조, 컴포넌트 책임 |
| | [hybrid-msa](docs/01-architecture/hybrid-msa.md) | 모놀리스/MSA 경계, 이벤트 흐름 |
| | [network-design](docs/01-architecture/network-design.md) | CIDR, 서브넷, VPN, 보안그룹 |
| | [data-architecture](docs/01-architecture/data-architecture.md) | DB, 캐시, Kafka 토픽, CDC 대상 |
| 의사결정 | [ADR 목록](docs/02-adr/README.md) | 기술 선택 이유 (Why / Why not) |
| 개발 | [development-guide](docs/03-development/development-guide.md) | 로컬 환경, 브랜치/커밋 규칙 |
| | [api-spec](docs/03-development/api-spec.md) | API 초안 |
| | [domain-model](docs/03-development/domain-model.md) | 포인트 원장 모델, 멱등성 |
| 인프라 | [terraform-guide](docs/04-infrastructure/terraform-guide.md) | 모듈 구조, State 전략 |
| | [cicd-pipeline](docs/04-infrastructure/cicd-pipeline.md) | CI/CD, GitOps 흐름 |
| | [security](docs/04-infrastructure/security.md) | IAM, 암호화, 시크릿, 망분리 |
| 운영 | [observability](docs/05-operations/observability.md) | 메트릭, 로그, 알람, SLO |
| | [finops](docs/05-operations/finops.md) | 비용 모델, 절감 전략 |
| | [runbooks](docs/05-operations/runbooks/) | 이벤트 당일, 장애 대응 |
| 재해복구 | [dr-strategy](docs/06-disaster-recovery/dr-strategy.md) | Pilot Light, 선택적 복구 |
| | [dr-runbook](docs/06-disaster-recovery/dr-runbook.md) | Failover / Failback 절차 |
| | [dr-drill-plan](docs/06-disaster-recovery/dr-drill-plan.md) | DR 훈련 계획, 측정 방법 |
| 테스트 | [test-strategy](docs/07-testing/test-strategy.md) | 부하/카오스/DR 테스트 |
| 팀 | [github-workflow](docs/team/github-workflow.md) | 팀 GitHub 운영 규칙 |
| | [ai-collaboration](docs/team/ai-collaboration.md) | AI 공통 지침 운영 |
| 관리 | [roadmap](docs/08-project-management/roadmap.md) | 단계별 일정, WBS |
| | [risk-register](docs/08-project-management/risk-register.md) | 리스크와 대응 |
| | [interview-qa](docs/08-project-management/interview-qa.md) | 예상 질문 & 방어 논리 |

## 4. 레포지토리 구성

| 레포 | 내용 |
|---|---|
| **point-infra** (이 레포) | Terraform, K8s(GitOps), CDC, DR, 부하 테스트, **설계 문서 · 팀 규칙 원본** |
| [point-backend](https://github.com/CHANGE_ME_ORG/point-backend) | Spring Boot — monolith, event-service, OpenAPI |
| [point-frontend](https://github.com/CHANGE_ME_ORG/point-frontend) | React + Vite + TypeScript SPA |

분리 이유: [ADR-0012](docs/02-adr/0012-polyrepo-split.md)

```
point-infra/
├── AGENTS.md / CLAUDE.md / GEMINI.md   # AI 공통 지침 (팀원 AI 충돌 방지)
├── team/ai/                 # 공통 AI 규칙 원본, 대화형 AI 세션 프롬프트
├── docs/
│   ├── 00~08-*/             # 개요, 아키텍처, ADR, 개발, 인프라, 운영, DR, 테스트, 관리
│   └── team/                # GitHub 운영 규칙, AI 협업 가이드, 온보딩
├── infra/terraform/
│   ├── bootstrap/           # State 저장소 (S3 / GCS)
│   ├── modules/{aws,gcp,shared}/
│   └── envs/{aws-main, gcp-dr-standby, gcp-dr-compute}/
├── k8s/{base, overlays/{aws,gcp-dr}, platform, argocd}/
├── cdc/                     # Debezium Source / JDBC Sink
├── load-test/k6/
├── scripts/                 # dr/, setup-github.sh, sync-ai-rules.sh
└── .github/                 # 워크플로, PR·이슈 템플릿, CODEOWNERS, labels
```

## 5. 팀 규칙 (필독)

| 문서 | 내용 |
|---|---|
| [AGENTS.md](AGENTS.md) | 사람·AI 공통 작업 규칙 (Decision Lock, 금지 사항, 범위 규칙) |
| [github-workflow.md](docs/team/github-workflow.md) | 이슈 → 브랜치 → PR → 리뷰 → 머지, 브랜치 보호, 교차 레포 변경 |
| [ai-collaboration.md](docs/team/ai-collaboration.md) | AI 도구별 설정, 프롬프트 템플릿, 검증 체크리스트 |
| [onboarding.md](docs/team/onboarding.md) | 신규 팀원 Day 1 |

## 6. 진행 현황

로드맵: [docs/08-project-management/roadmap.md](docs/08-project-management/roadmap.md)

- [ ] Phase 0 — 설계 및 문서화
- [ ] Phase 1 — 애플리케이션 MVP (로컬)
- [ ] Phase 2 — AWS Main 인프라 (Terraform)
- [ ] Phase 3 — EKS + GitOps + 오토스케일링
- [ ] Phase 4 — CDC 복제 + GCP Standby
- [ ] Phase 5 — DR Failover 자동화 + 훈련
- [ ] Phase 6 — 부하 테스트, 비용 분석, 회고
