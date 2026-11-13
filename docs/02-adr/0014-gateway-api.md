# ADR-0014: 트래픽 진입에 Gateway API 채택
- 상태: Accepted · 날짜: 2026-11-13

## 맥락
같은 매니페스트로 AWS(EKS)와 GCP DR(GKE)에 배포해야 한다(ADR-0003, 0010). 경로 규칙이 클라우드 전용 어노테이션에 묶이면
환경마다 라우팅 정의가 갈라지고, DR 전환 시 검증되지 않은 설정이 쓰이게 된다.

## 결정
L7 진입점은 **Kubernetes Gateway API** 로 정의한다.
| 리소스 | 위치 | 내용 |
|---|---|---|
| `HTTPRoute` | 각 오버레이 (규칙은 클라우드 중립) | `/api/events` → event-service(DR: maintenance), `/api` → monolith, `/` → web |
| `Gateway` | 각 오버레이 | 리스너 (도메인·ACM 확보 후 HTTPS 443) |
| `GatewayClass` | AWS: `gateway.k8s.aws/alb` · GCP: `gke-l7-global-external-managed` | 컨트롤러 |
| `LoadBalancerConfiguration` / `TargetGroupConfiguration` | AWS 오버레이 | ALB 이름·SG, 대상 그룹(ip)·헬스체크 |

- AWS 컨트롤러: AWS Load Balancer Controller (Gateway API 표준 CRD 는 같은 ArgoCD Application 에서 설치)
- WAF: Gateway 설정은 Web ACL ARN 을 요구 → 공개 저장소에 계정 ID 를 두지 않기 위해 Terraform 이 ALB 에 직접 연결

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| Ingress (ALB / GCE) | 운영 사례 많음 | 기능 추가 동결, 핵심 설정이 벤더 어노테이션 → 환경별 정의가 달라짐 | DR 이식성 |
| 서비스 메시 Ingress Gateway | 세밀한 트래픽 제어 | 메시 운영 부담 | 현재 요구 대비 과함 |

## 결과
- (+) 라우팅 규칙이 두 클라우드에서 같은 형태 → DR 전환 시 차이는 GatewayClass·인프라 설정뿐
- (+) 인프라(Gateway)와 앱 라우트(HTTPRoute) 역할 분리
- (−) AWS 전용 CRD(LoadBalancerConfiguration 등) 학습 필요
