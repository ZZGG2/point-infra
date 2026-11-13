# ADR-0015: 프론트엔드를 web 파드로 서빙
- 상태: Accepted · 날짜: 2026-11-13

## 맥락
도메인은 Route 53 으로 연결한다. API 와 화면이 같은 출처(`/api/**`)를 쓰므로 진입점 하나에서 경로로 나누는 것이 가장 단순하다.
DR 시에도 화면이 같은 방식으로 떠야 한다.

## 결정
point-frontend 빌드 결과를 **nginx(non-root) 컨테이너 이미지(web)** 로 만들고, EKS·GKE 에 파드로 배포한다.
- 이미지: `point-frontend/Dockerfile` (nginx-unprivileged, 8080, `/healthz`), ECR + Artifact Registry 이중 푸시
- 라우팅: Gateway(HTTPRoute)의 `/` 규칙 → `web` Service
- 매니페스트: `k8s/base/web` (AWS·GCP DR 오버레이 공통)

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| S3 + CloudFront (GCS + Cloud CDN) | 엣지 캐시, 노드 불필요 | 클라우드별 호스팅·배포 경로가 따로, 도메인·인증서 구성 이중화 | 진입점·배포 경로 단일화 우선 |

## 결과
- (+) 배포 경로 단일화(이미지 → ArgoCD), AWS·GCP 동일 이미지
- (+) 진입점 하나(Gateway)에서 화면·API 라우팅, Route 53 레코드 단순화
- (−) 정적 파일도 클러스터 리소스 사용 (요청 50m CPU / 64Mi 수준). 글로벌 캐시가 필요해지면 CDN 을 앞단에 추가
