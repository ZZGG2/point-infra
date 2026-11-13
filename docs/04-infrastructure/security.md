# 보안 설계

## 1. 계층별 통제

| 계층 | 통제 | 구현 |
|---|---|---|
| 엣지 | DDoS, 봇, Rate Limit | AWS Shield Standard, WAF Managed Rules + Bot Control, Rate-based rule |
| 네트워크 | 망분리, 최소 개방 | Private Subnet, SG 최소 포트, VPC Endpoint, 클라우드 간 VPN |
| 계정/권한 | 최소 권한, 장기 키 금지 | IAM Role + OIDC, EKS Pod Identity, GKE Workload Identity |
| K8s | 파드 권한 최소화 | Pod Security Standards(restricted), NetworkPolicy, non-root 이미지 |
| 데이터 | 저장 암호화 | KMS(Aurora, MSK, EBS, S3), GCP CMEK(Cloud SQL) |
| 데이터 | 전송 암호화 | TLS 1.2+, Aurora `rds.force_ssl=1`, Cloud SQL SSL 필수 |
| 데이터 | 개인정보 | 이름·연락처 컬럼 애플리케이션 레벨 암호화, 로그 마스킹 |
| 시크릿 | 코드/이미지에 시크릿 금지 | Secrets Manager / Secret Manager + External Secrets Operator |
| 공급망 | 이미지 취약점 | Trivy(CI, Critical 시 실패), ECR 스캔 |
| 감사 | 변경 추적 | CloudTrail, GCP Audit Logs, EKS audit log, Git 이력 |

## 2. IAM 역할 목록 (AWS)

| Role | 신뢰 주체 | 권한 요약 |
|---|---|---|
| `gha-terraform` | GitHub OIDC (main 브랜치) | 인프라 프로비저닝 |
| `gha-ecr-push` | GitHub OIDC | ECR push |
| `karpenter-controller` | Pod Identity | EC2 생성/삭제, SQS 인터럽트 큐 |
| `external-secrets` | Pod Identity | 특정 경로 Secrets Manager 읽기 |
| `monolith-app` | Pod Identity | MSK IAM 인증, S3 특정 prefix |
| `msk-connect-debezium` | MSK Connect | MSK, Secrets Manager(DB 자격증명) |

## 3. DB 계정 분리

| 계정 | 위치 | 권한 |
|---|---|---|
| `app_rw` | Aurora | 앱 스키마 DML |
| `debezium` | Aurora | REPLICATION, 대상 테이블 SELECT |
| `sink_writer` | Cloud SQL | 평시 유일한 쓰기 계정 |
| `app_rw` | Cloud SQL | **평시 NOLOGIN → Failover 시 LOGIN 전환** |

## 4. 보안 점검 체크리스트
- [ ] 퍼블릭 S3 버킷 0개
- [ ] 0.0.0.0/0 Inbound SG는 ALB 443만 (CloudFront prefix list로 제한 시 0개)
- [ ] IAM Access Key 0개 (CI 포함)
- [ ] checkov High 이상 0건 또는 예외 사유 문서화
- [ ] 컨테이너 root 실행 0개
