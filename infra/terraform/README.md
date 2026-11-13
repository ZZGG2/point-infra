# infra/terraform

상세 가이드: [docs/04-infrastructure/terraform-guide.md](../../docs/04-infrastructure/terraform-guide.md)

| 경로 | State | 생명주기 |
|---|---|---|
| `bootstrap/aws` | local (1회) | 상시 — State 버킷 (`prevent_destroy`) |
| `bootstrap/gcp` | local → 이후 GCS | 1회 |
| `envs/aws-main` | S3 | 상시 (학습 중 비작업 시 destroy 가능) |
| `envs/gcp-dr-standby` | GCS | 상시 |
| `envs/gcp-dr-compute` | GCS | **장애/훈련 시에만** |

## 구현 상태

| 모듈 | 상태 | 비고 |
|---|---|---|
| aws/vpc | ✅ | 3-tier, NAT 1개(학습), S3 Gateway + Interface Endpoint(ecr.api/dkr, sts, secretsmanager, logs) |
| aws/eks | ✅ | 1.35, core Managed NodeGroup(AL2023, On-Demand), Pod Identity Agent, API 엔드포인트는 관리자 IP 만 |
| aws/karpenter | ✅ | IAM·SQS·EventBridge + Helm. NodePool/EC2NodeClass 는 `k8s/platform/karpenter` |
| aws/aurora | ✅ | PG 16, 논리 복제·force_ssl, KMS, 앱 계정 `app_rw` 자동 생성(Data API) |
| aws/elasticache | ✅ | Valkey 7.2, Primary+Replica Multi-AZ, 전송/저장 암호화 |
| aws/msk | ✅ | 3 브로커, TLS(9094)+IAM(9098), 토픽 자동 생성. MSK Connect(CDC) 🟡 |
| aws/ecr | ✅ | 불변 태그, 푸시 시 스캔, 수명주기 |
| aws/edge | ✅ | CloudFront(S3 정적 + `/api/*` → ALB) + WAF. Route 53/ACM 🟡 (도메인 필요) |
| aws/argocd-bootstrap | ✅ | ArgoCD + Application 등록 (애드온: LB Controller, External Secrets, KEDA) |
| gcp/argocd-bootstrap | ✅ | |
| gcp/network, cloudsql, gke, shared/vpn | 🟡 | |

## AWS Main 구축 (로컬 실행)

사전 조건: Terraform ≥ 1.10, AWS CLI(인증), Docker(실행 중), Node 20+, PowerShell 7, GitOps 저장소(`git_repo_url`)에 `main` push 완료

```powershell
# 0. State 버킷 (최초 1회)
cd infra/terraform/bootstrap/aws
terraform init; terraform apply -var bucket_name=point-platform-tfstate-<account_id>

# 1. 설정 (둘 다 .gitignore 대상)
cd ../../envs/aws-main
cp backend.hcl.example backend.hcl            # bucket 이름 수정
cp terraform.tfvars.example terraform.tfvars  # 검증 시 apps_path = "k8s/overlays/aws-demo"

# 2. 구축: ECR → 이미지 빌드·푸시 → terraform apply → 프론트 업로드 (40분 안팎)
../../../../scripts/aws/up.ps1

# 3. 삭제: ArgoCD 앱(→ ALB, Karpenter 노드) 정리 후 terraform destroy
../../../../scripts/aws/down.ps1
```

`terraform apply` 한 번 안에서 일어나는 일: 인프라 생성 → ArgoCD 설치·앱 등록 → ArgoCD 가 Git 에서 Ingress 를
동기화 → LB Controller 가 ALB 생성 → Terraform 이 ALB 를 찾아 CloudFront 오리진으로 연결.

## 앱 연결 방식

| 값 | 위치 | 앱에 전달 |
|---|---|---|
| DB URL·계정, Kafka/Redis 엔드포인트 | Secrets Manager `point-main/{monolith,event-service}` (Terraform 기록) | External Secrets → Secret → `envFrom` |
| ECR 이미지 주소·태그 | Terraform → ArgoCD Application `kustomize.images` | 공개 저장소에 계정 ID 를 남기지 않기 위함 |
| LB Controller 의 VPC ID 등 | Terraform → ArgoCD Application Helm 값 | |

## 설계 문서와 다른 점 (앱 현재 구현에 맞춤)

| 항목 | 설계 | 현재 | 이유 / 후속 |
|---|---|---|---|
| MSK 인증 | IAM 9098 | TLS 9094 (IAM 리스너도 열어 둠) | 앱에 `aws-msk-iam-auth` 없음 → 백엔드에 추가하면 IAM 전환 |
| ElastiCache | Cluster mode | Cluster mode 비활성(1 샤드 + Replica) | 앱이 단일 엔드포인트 설정 사용, Lua 다중 키 |
| ALB 리스너 | HTTPS 443 | HTTP 80 (CloudFront 에서 TLS 종료, ALB 는 CloudFront 대역만 허용) | 도메인·ACM 없음 |
| Route 53 Failover | 있음 | 없음 | 도메인 필요 (GCP DR 과 함께) |
| MSK Connect(Debezium) | 있음 | 없음 | GCP Cloud SQL·VPN 구축 후 |
