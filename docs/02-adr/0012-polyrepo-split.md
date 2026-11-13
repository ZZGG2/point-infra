# ADR-0012: 레포지토리 분리 (infra / backend / frontend)
- 상태: Accepted · 날짜: 2026-11-05 · 갱신: point-frontend 배포 산출물은 ADR-0015 에 따라 web 컨테이너 이미지 (ECR + Artifact Registry)

## 맥락
팀 공동 개발로 전환하면서 인프라·백엔드·프론트 작업자가 동시에 같은 레포를 수정하게 됐다. 빌드 도구, CI 트리거, 리뷰어, 배포 주기가 영역마다 다르다.

## 결정
| 레포 | 내용 | 배포 산출물 |
|---|---|---|
| `point-infra` | Terraform, K8s 매니페스트(GitOps 원천), CDC, DR 스크립트, 부하 테스트, **설계 문서 전체**, 팀 공통 규칙 원본 | 클라우드 리소스, 클러스터 상태 |
| `point-backend` | monolith, event-service (Gradle 멀티 모듈), OpenAPI 명세, Kafka 메시지 스키마 | 컨테이너 이미지 |
| `point-frontend` | React SPA | 정적 파일 (S3 + GCS) |

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| 모노레포 유지 | 원자적 변경, 단일 이슈 트래커 | CI 경로 필터 복잡, 권한 분리 어려움, 리뷰 알림 과다 | 팀 규모·역할 분리 |
| 앱 레포 + GitOps 레포 + IaC 레포 (4개) | 역할 극단 분리 | 1개 팀엔 과함 | infra 레포가 IaC + GitOps 겸함 |
| **3개 레포** | 역할별 소유권, 독립 CI, 배포 기록은 infra 한 곳 | 레포 간 계약(API) 관리 필요 | **채택** |

## 결과
- (+) CODEOWNERS·브랜치 보호를 레포 성격에 맞게 다르게 설정 가능
- (+) 배포 이력은 point-infra 커밋 로그 하나로 추적
- (−) API 변경 시 레포 간 조율 필요 → [github-workflow §8 교차 레포 변경 규칙](../team/github-workflow.md)
- (−) 공통 규칙(AI, PR 템플릿) 중복 → `scripts/sync-ai-rules.sh`로 원본 1곳에서 동기화
