# ADR-0009: Terraform(인프라) / ArgoCD(워크로드) 역할 분리
- 상태: Accepted · 날짜: 2026-11-05

## 결정
| 레이어 | 도구 | 범위 |
|---|---|---|
| 클라우드 리소스 | Terraform | VPC, EKS/GKE, DB, Kafka, IAM, DNS |
| 클러스터 부트스트랩 | Terraform (helm provider) | ArgoCD 설치 + root Application 1개만 |
| 플랫폼 애드온 + 앱 | ArgoCD (Git) | Karpenter NodePool, KEDA, External Secrets, monitoring, monolith, event-service |

## 이유
- Terraform으로 K8s 리소스를 전부 관리하면 Drift 감지·롤백이 약하고, plan이 느려진다.
- 경계를 "ArgoCD 설치까지"로 고정하면, **DR 시 Terraform은 클러스터 + ArgoCD만 만들고 나머지는 Git이 자동으로 채운다** → RTO 단축, 재현성 확보.
