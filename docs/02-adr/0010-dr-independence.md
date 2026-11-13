# ADR-0010: DR 경로의 AWS 비의존성
- 상태: Accepted · 날짜: 2026-11-05

## 맥락
"AWS가 죽었을 때 실행하는 DR 절차"가 AWS 리소스에 의존하면 DR은 동작하지 않는다. 흔히 놓치는 의존성을 전수 점검했다.

## 결정
| 의존성 | AWS에 두면 생기는 문제 | 결정 |
|---|---|---|
| Terraform State (GCP 환경) | S3 접근 불가 → plan/apply 불가 | **GCS 버킷**에 저장 |
| 컨테이너 이미지 | ECR pull 불가 | CI에서 **ECR + Artifact Registry 이중 푸시** |
| ArgoCD | EKS 안의 ArgoCD 사망 | **GKE에 ArgoCD를 새로 설치** (Terraform helm) |
| 시크릿 | Secrets Manager 접근 불가 | **GCP Secret Manager**에 사전 등록, External Secrets로 주입 |
| CI/CD 실행 환경 | AWS 내 러너 사망 | **GitHub-hosted runner** 사용 |
| GCP 인증 | AWS IAM 기반 연동 | GitHub OIDC → GCP Workload Identity Federation |
| DNS | Route 53 (글로벌 서비스) | Route 53 유지 + 장애 대비 **도메인 등록기관에서 NS 변경 절차** 문서화 |

## 결과
- (+) AWS 전체 장애에서도 DR 파이프라인 동작
- (−) 이미지 이중 푸시, 시크릿 이중 관리 비용 → CI 자동화로 흡수
