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
| aws/vpc, aws/eks, aws/aurora, gcp/argocd-bootstrap | ✅ |
| aws/karpenter, elasticache, msk, ecr, edge, gcp/network, cloudsql, gke, shared/vpn | 🟡 |
