# Terraform 가이드

## 1. 디렉터리 구조

> 아래 구조는 목표 설계 기준이다. 현재 스캐폴딩과의 차이(aurora → rds, edge → waf 등): [infra/terraform/README](../../infra/terraform/README.md)

```
infra/terraform/
├── bootstrap/
│   ├── aws/              # S3 state 버킷 (버전관리, 암호화)
│   └── gcp/              # GCS state 버킷 (AWS 비의존)
├── modules/
│   ├── aws/
│   │   ├── vpc/          # 3-tier subnet, NAT, VPC Endpoints
│   │   ├── eks/          # 클러스터, Managed NodeGroup(AL2023), Pod Identity, 애드온
│   │   ├── karpenter/    # IAM, SQS(Interruption), Helm
│   │   ├── rds/          # PostgreSQL 16, 파라미터 그룹(logical replication, force_ssl), KMS  ※ 현재 스캐폴딩: aurora/
│   │   ├── elasticache/
│   │   ├── msk/          # 클러스터 + MSK Connect(Debezium)
│   │   ├── ecr/          # monolith, event-service, web
│   │   ├── waf/          # 리전 WAF + Gateway ALB 연결  ※ 현재 스캐폴딩: edge/
│   │   └── argocd-bootstrap/  # ArgoCD + Application 등록 (LB Controller·External Secrets·KEDA·앱)  ※ 구현 예정
│   ├── gcp/
│   │   ├── network/      # VPC, subnet, PSA, Static IP
│   │   ├── cloudsql/
│   │   ├── gke/
│   │   └── argocd-bootstrap/  # helm_release + root Application
│   └── shared/
│       └── vpn/          # AWS VPN ↔ GCP HA VPN (양쪽 provider 사용)
└── envs/
    ├── aws-main/         # state: S3
    ├── gcp-dr-standby/   # state: GCS (상시)
    └── gcp-dr-compute/   # state: GCS (장애 시 apply, 복구 후 destroy)
```

## 2. State 전략 (가장 중요)

| 환경 | Backend | 이유 |
|---|---|---|
| `aws-main` | S3 (`use_lockfile = true`, Terraform 1.10+ 네이티브 락) | 표준 |
| `gcp-dr-standby` | GCS | AWS 장애와 무관하게 접근 |
| `gcp-dr-compute` | GCS | **DR 실행 시 AWS 접근 불가 상황에서 apply 해야 함** |

- 환경 간 값 참조는 `terraform_remote_state` 대신 **명시적 변수/출력 파일**로 전달 → DR 시 AWS state 조회 실패로 막히는 상황 방지.
  - 예: `gcp-dr-compute`는 `gcp-dr-standby`(GCS)의 출력만 참조한다.

## 3. 환경 분리 이유 — 왜 GCP를 standby / compute 둘로 나눴나

| 구분 | standby | compute |
|---|---|---|
| 생명주기 | 항상 존재 | 장애 시 생성 → 복구 후 삭제 |
| 리소스 | VPC, Cloud SQL, VPN, Static IP, Artifact Registry, Secret Manager | GKE, Node Pool, Cloud NAT, ArgoCD |
| apply 빈도 | 낮음 | DR 훈련/실제 장애 |
| blast radius | 실수로 destroy 시 DR DB 소실 → `prevent_destroy` | destroy가 정상 동작 |

## 4. 코딩 규칙

- 모든 모듈: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
- provider / 모듈 버전 고정 (`~>` 사용)
- 공통 태그/라벨: `project=point-platform`, `env`, `owner`, `cost-center`, `managed-by=terraform`
- `terraform fmt`, `tflint`, `checkov`(보안 정적 분석)을 CI에서 강제
- 콘솔 수동 변경 금지 → 주 1회 `plan` Drift 감지 워크플로

## 5. 실행 순서 (최초 구축)

```bash
# 1. state 저장소
cd infra/terraform/bootstrap/aws && terraform init && terraform apply
cd infra/terraform/bootstrap/gcp && terraform init && terraform apply
# 2. Main
cd infra/terraform/envs/aws-main && terraform init && terraform apply
# 3. DR Standby (VPN은 양쪽 출력 필요 → 변수로 AWS VPN 정보 전달)
cd infra/terraform/envs/gcp-dr-standby && terraform init && terraform apply
# 4. DR Compute — 평시 실행하지 않음. DR 훈련 시 dr-failover 워크플로가 실행.
```

### 구현 시 놓치기 쉬운 순서·인증 요구사항
| 항목 | 요구사항 |
|---|---|
| EKS 애드온 순서 | `vpc-cni`(Prefix Delegation), `eks-pod-identity-agent` 는 `before_compute = true` — 노드 그룹보다 먼저 설치돼야 첫 노드부터 설정이 적용된다. 늦게 붙으면 기존 노드는 IP 한도가 그대로이고 Pod Identity 자격 증명을 못 받는다 |
| MSK 인증 (IAM) | 클러스터를 IAM 인증으로 만들면 클라이언트는 포트 9098 + `SASL_SSL` / `AWS_MSK_IAM` 으로 접속해야 한다. 앱(monolith, event-service)에 `software.amazon.msk:aws-msk-iam-auth` 와 aws 프로필 Kafka 설정이 필요하고(현재 point-backend 에 없음 → backend 이슈로 선행), 각 ServiceAccount 에 `kafka-cluster:Connect/DescribeTopic/ReadData/WriteData/DescribeGroup/AlterGroup` 권한의 Pod Identity Association 을 둔다. MSK Connect(Debezium) 는 서비스 실행 역할에 같은 권한을 준다 |

## 6. 비용 안전장치

- 학습 기간에는 `aws-main`도 **작업 종료 시 destroy** 가능하도록 설계 (데이터는 스냅샷)
- AWS Budgets / GCP Budget 알림: 월 예산 50%, 80%, 100%
