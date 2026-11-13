# infra/terraform

상세 가이드: [docs/04-infrastructure/terraform-guide.md](../../docs/04-infrastructure/terraform-guide.md)

| 경로 | State | 생명주기 |
|---|---|---|
| `bootstrap/aws` | local → 이후 S3로 마이그레이션 | 1회 |
| `bootstrap/gcp` | local → 이후 GCS | 1회 |
| `envs/aws-main` | S3 | 상시 (학습 중 비작업 시 destroy 가능) |
| `envs/gcp-dr-standby` | GCS | 상시 |
| `envs/gcp-dr-compute` | GCS | **장애/훈련 시에만** |

구현 상태: ✅ 초안 작성 · 🟡 TODO 스텁
| 모듈 | 상태 |
|---|---|
| aws/vpc, aws/eks, aws/aurora (→ rds 로 교체 예정), gcp/argocd-bootstrap | ✅ |
| aws/karpenter, elasticache, msk, ecr, edge (→ waf 로 교체 예정), gcp/network, cloudsql, gke, shared/vpn | 🟡 |

## 설계(ADR) ↔ 현재 스캐폴딩 차이

아래 스캐폴딩은 ADR-0013~0015 이전 설계로 작성돼 있다. **실제 구현 단계에서 교체**하며, 그 전까지는 코드를 바꾸지 않는다. 문서(docs/)는 목표 설계 기준으로 쓰여 있다.

| 목표 설계 (문서 기준) | 현재 스캐폴딩 | 근거 |
|---|---|---|
| `modules/aws/rds` — RDS for PostgreSQL 16 Multi-AZ | `modules/aws/aurora` (Aurora 클러스터), `envs/aws-main` 의 `module "aurora"`, `output "aurora_endpoint"` | ADR-0013 |
| `modules/aws/waf` — 리전 WAF + Gateway ALB 연결 | `modules/aws/edge` (Route 53·ACM·CloudFront·WAF 스텁, CloudFront 는 사용하지 않음) | ADR-0014, 0015 |
| `modules/aws/argocd-bootstrap` | 없음 (`modules/gcp/argocd-bootstrap` 만 존재) | ADR-0009 |
| `k8s/overlays/{aws,gcp-dr}/gateway.yaml` — Gateway + HTTPRoute | `k8s/overlays/{aws,gcp-dr}/ingress.yaml` (Ingress) | ADR-0014 |
| `k8s/base/web` — 프론트엔드 web 파드 | 없음 | ADR-0015 |
| `k8s/overlays/aws/db-init.yaml` — `app_rw` 생성 Sync Job | 없음 | ADR-0013 |

- 동작 확인용 구현은 이 레포가 아니라 `point-cloud-test/aws-eks` 에서 한다.
