# infra/terraform

상세 가이드: [docs/04-infrastructure/terraform-guide.md](../../docs/04-infrastructure/terraform-guide.md)

| 경로 | State | 생명주기 |
|---|---|---|
| `bootstrap/aws` | local (1회) | 상시 — State 버킷 (`prevent_destroy`) |
| `bootstrap/gcp` | local → 이후 GCS | 1회 |
| `envs/aws-main` | S3 | 상시 (학습 중 비작업 시 destroy) |
| `envs/gcp-dr-standby` | GCS | 상시 |
| `envs/gcp-dr-compute` | GCS | **장애/훈련 시에만** |

## AWS Main 구성

```
사용자 ──▶ WAF ──▶ ALB (Gateway API, AWS Load Balancer Controller)
                     ├─ /api/events/** → event-service (Karpenter Spot 노드) ──▶ Valkey, MSK
                     ├─ /api/**        → monolith      (core 노드)          ──▶ RDS PostgreSQL, MSK 소비
                     └─ /**            → web           (core 노드, nginx SPA)
```

| 모듈 | 내용 |
|---|---|
| `aws/vpc` | 3-tier(Public / Private-App /19 / Private-Data), NAT, S3 Gateway Endpoint, Interface Endpoint(선택) |
| `aws/eks` | EKS 1.35, core Managed NodeGroup(AL2023, On-Demand), Pod Identity Agent, API 엔드포인트는 관리자 IP 만 |
| `aws/karpenter` | IAM·SQS·EventBridge + Helm. NodePool/EC2NodeClass 는 `k8s/platform/karpenter` |
| `aws/rds` | PostgreSQL 16, `rds.logical_replication=1`, `rds.force_ssl=1`, gp3·KMS, Multi-AZ(변수) |
| `aws/elasticache` | Valkey 7.2, 전송/저장 암호화, Replica 수 변수(0 = 단일 노드) |
| `aws/msk` | 3 브로커, TLS(9094) + IAM(9098), 토픽 자동 생성. MSK Connect(CDC)는 GCP DR 구축 시 |
| `aws/ecr` | monolith, event-service, web — 불변 태그, 푸시 시 스캔, 수명주기 |
| `aws/waf` | 리전 WAF(IP Rate Limit, AWS Managed Rules) + Gateway ALB 연결 |
| `aws/argocd-bootstrap` | ArgoCD + Application 등록: LB Controller(+Gateway API CRD), External Secrets, KEDA, platform, apps |
| `gcp/argocd-bootstrap` | GKE ArgoCD + root Application |
| `gcp/network`, `cloudsql`, `gke`, `shared/vpn` | 🟡 TODO |

## 구축 (로컬 실행)

사전 조건: Terraform ≥ 1.10, AWS CLI(인증), Docker(실행 중), PowerShell 7, GitOps 저장소(`git_repo_url`)에 `main` push 완료

```powershell
# 0. State 버킷 (최초 1회)
cd infra/terraform/bootstrap/aws
terraform init; terraform apply -var bucket_name=point-platform-tfstate-<account_id>

# 1. 설정 (둘 다 .gitignore 대상)
cd ../../envs/aws-main
cp backend.hcl.example backend.hcl            # bucket 이름 수정
cp terraform.tfvars.example terraform.tfvars  # 검증 시 apps_path = "k8s/overlays/aws-demo"

# 2. 구축: ECR → 이미지 3종 빌드·푸시 → terraform apply (plan 확인 후 yes)
../../../../scripts/aws/up.ps1

# 3. 접속 주소
terraform output web_url

# 4. 삭제: ArgoCD 앱(→ ALB, Karpenter 노드) 정리 후 terraform destroy
../../../../scripts/aws/down.ps1
```

`terraform apply` 한 번 안에서: 인프라 생성 → ArgoCD 설치·Application 등록 → ArgoCD 가 Git 에서 Gateway/HTTPRoute 동기화
→ LB Controller 가 ALB(`point-main-alb`) 생성 → Terraform 이 ALB 를 찾아 WAF 연결.

## 앱 연결 방식

| 값 | 위치 | 앱에 전달 |
|---|---|---|
| DB URL·`app_rw` 계정, Kafka/Redis 엔드포인트 | Secrets Manager `point-main/{monolith,event-service}` | External Secrets → Secret → `envFrom` |
| DB 마스터 계정 | Secrets Manager `point-main/db-bootstrap` | `db-init` Job(ArgoCD Sync hook)만 사용 → `app_rw` 생성 |
| ECR 이미지 주소·태그 | Terraform → ArgoCD Application `kustomize.images` | 공개 저장소에 계정 ID 를 두지 않음 |
| LB Controller VPC ID·webhook 인증서 | Terraform → ArgoCD Application Helm 값 | 인증서는 Terraform `tls` 로 고정 생성 |
| WAF | Terraform `aws/waf` → ALB 연결 | Gateway 설정은 ARN 을 요구하므로 Git 에 두지 않음 |

## 앱 런타임 설정

| 항목 | 값 | 이유 |
|---|---|---|
| Kafka | TLS 리스너(9094), `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` | 앱에 `aws-msk-iam-auth` 미포함. 추가하면 IAM(9098) 사용 |
| Redis | 단일 엔드포인트, `SPRING_DATA_REDIS_SSL_ENABLED=true`, Cluster mode 비활성 | 앱이 `spring.data.redis.host` + 다중 키 Lua 사용 |
| DB | `sslmode=require` | `rds.force_ssl=1` |
| 진입 | ALB HTTP 80, `alb_ingress_cidrs`(기본: 실행 PC IP)만 허용 | Route 53 도메인 + ACM 후 HTTPS 443 공개 |

## 학습 환경 비용 설정 (`terraform.tfvars` 로 운영값 전환)

| 변수 | 학습 기본값 | 운영 권장 |
|---|---|---|
| `core_node_count` | 1 (t3.large) | 2+ |
| `rds_instance_class` / `rds_multi_az` | `db.t4g.micro` / false | `db.m7g.large` 이상 / true |
| `redis_node_type` / `redis_replicas` | `cache.t4g.micro` / 0 | `cache.m7g.large` / 1+ |
| `enable_interface_endpoints` | false (NAT 경유) | true |
| `single_nat_gateway` | true | false |
| 앱·애드온 레플리카 | 1 (`overlays/aws-demo`, `addon_replicas`) | 2+ |

참고: EKS 모듈은 노드 그룹 `desired_size` 변경을 무시한다. `core_node_count` 를 줄인 뒤에는
`aws eks update-nodegroup-config --scaling-config minSize=1,desiredSize=1,maxSize=4` 로 현재 대수를 맞춘다.

## TODO

| 항목 | 조건 |
|---|---|
| Route 53 호스팅 영역 + ACM, Gateway HTTPS 443 리스너 | 도메인 확보 |
| MSK Connect(Debezium source / JDBC sink), Site-to-Site VPN | GCP DR(`gcp-dr-standby`) 구축 |
| `versions.tf` 의 `aws.us_east_1` provider 제거 | 이전 us-east-1 리소스 삭제 apply 완료 후 |
