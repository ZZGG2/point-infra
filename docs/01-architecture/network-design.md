# 네트워크 설계

## 1. CIDR 계획 (겹침 금지 — VPN 라우팅 전제)

| 환경 | 대역 | 용도 |
|---|---|---|
| AWS Main VPC | `10.10.0.0/16` | 운영 |
| GCP DR VPC | `10.20.0.0/16` | DR |
| GKE Pod (secondary) | `10.24.0.0/14` | DR 파드 |
| GKE Service (secondary) | `10.28.0.0/20` | DR 서비스 |
| GCP Private Service Access (Cloud SQL) | `10.30.0.0/20` | Cloud SQL Private IP |
| 로컬 / Docker | `172.16.0.0/12` | 개발 |
| 예약 (향후 리전 확장) | `10.11.0.0/16` ~ `10.19.0.0/16` | - |

> 이 표는 가장 먼저 확정하고 바꾸지 않는다. CIDR 변경은 VPC 재생성 = 사실상 전체 재구축.

## 2. AWS 서브넷 (3 AZ: 2a / 2b / 2c)

| 계층 | AZ-a | AZ-b | AZ-c | 크기 | 배치 리소스 |
|---|---|---|---|---|---|
| Public | 10.10.0.0/24 | 10.10.1.0/24 | 10.10.2.0/24 | 251 IP | ALB, NAT GW |
| Private-App | 10.10.32.0/19 | 10.10.64.0/19 | 10.10.96.0/19 | 8,187 IP | EKS 노드/파드 (VPC CNI) |
| Private-Data | 10.10.128.0/24 | 10.10.129.0/24 | 10.10.130.0/24 | 251 IP | Aurora, Redis, MSK |
| (예약) | 10.10.160.0/19 ~ | | | | 향후 확장 |

**App 서브넷을 /19로 잡은 이유:** VPC CNI는 파드마다 VPC IP를 소비한다. 이벤트 피크에 Karpenter가 노드를 수십 대 띄우면 /24는 즉시 고갈된다. (대안: Prefix Delegation 활성화)

## 3. 라우팅 및 외부 통신

| 경로 | 구성 | 비고 |
|---|---|---|
| Private → 인터넷 | NAT Gateway | 데모: 1개 (비용), 운영 권장: AZ별 1개 |
| Private → AWS 서비스 | VPC Endpoint (S3 GW, ECR api/dkr, STS, Secrets Manager, CloudWatch Logs) | NAT 데이터 처리 비용 절감 + 망분리 |
| AWS ↔ GCP | AWS Site-to-Site VPN ↔ GCP HA VPN (터널 2개 이상, BGP) | CDC 복제 트래픽 전용 |

### HA VPN 구성
```
AWS VGW / TGW ──(Tunnel 1, 2)──┐
                               ├── GCP HA VPN Gateway (interface 0, 1) ── Cloud Router (BGP ASN 64514)
AWS Customer GW x2 ──(Tunnel 3, 4)┘
```
- GCP는 Cloud SQL Private IP 대역(`10.30.0.0/20`)을 Cloud Router 커스텀 광고로 AWS에 전달해야 한다. (Private Service Access 피어링 대역은 기본 광고되지 않음 → 커스텀 경로 광고 + 피어링 export 설정 필요)

## 4. 보안 그룹 (AWS)

| SG | Inbound | From |
|---|---|---|
| sg-alb | 443 | CloudFront Managed Prefix List |
| sg-eks-node | 모든 포트 | sg-alb, 자기 자신 |
| sg-aurora | 5432 | sg-eks-node, sg-msk-connect |
| sg-redis | 6379 | sg-eks-node |
| sg-msk | 9098 (IAM) | sg-eks-node, sg-msk-connect |
| sg-msk-connect | - (Outbound: Aurora 5432, MSK 9098, GCP 10.30.0.0/20:5432) | - |

## 5. GCP DR 네트워크

| 리소스 | 값 | 상시 여부 |
|---|---|---|
| VPC `dr-vpc` | custom mode | 상시 |
| Subnet `dr-gke` | 10.20.0.0/20 (+ secondary pod/svc) | 상시 (비용 없음) |
| Private Service Access | 10.30.0.0/20 | 상시 |
| HA VPN + Cloud Router | - | 상시 |
| Global Static IP `dr-ingress-ip` | - | 상시 (DNS 사전 등록용) |
| Cloud NAT | - | 장애 시 생성 |

## 6. DNS

| 레코드 | 유형 | Primary | Secondary |
|---|---|---|---|
| `api.<domain>` | A (Alias) / Failover | AWS ALB(또는 CloudFront) + Health Check | GCP Global Static IP |
| `www.<domain>` | A (Alias) / Failover | CloudFront (S3 정적 호스팅) | GCP External LB + Cloud Storage 백엔드 버킷 (Cloud CDN) |
| TTL | 60s | | |

- Secondary 레코드는 **평시에도 등록**해 둔다 (GCP Static IP를 미리 예약했기 때문에 가능).
- 단, 자동 Failover가 동작하지 않도록 Secondary를 Health Check 없이 두고, 전환 자체는 **Primary Health Check를 강제 실패(Inverted)로 만드는 방식**으로 운영자가 통제한다. (오탐에 의한 Split-brain 방지)
