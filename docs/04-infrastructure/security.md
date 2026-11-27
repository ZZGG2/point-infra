# 보안 설계

## 1. 계층별 통제

| 계층 | 통제 | 구현 |
|---|---|---|
| 엣지 | DDoS, 봇, Rate Limit | AWS Shield Standard, 리전 WAF(ALB 연결): Managed Rules(Common, IP Reputation, Known Bad Inputs) + Rate-based rule |
| 네트워크 | 망분리, 최소 개방 | Private Subnet, SG 최소 포트, VPC Endpoint, 클라우드 간 VPN |
| 계정/권한 | 최소 권한, 장기 키 금지 | IAM Role + OIDC, EKS Pod Identity, GKE Workload Identity |
| K8s | 파드 권한 최소화 | Pod Security Standards(restricted), NetworkPolicy, non-root 이미지 (현재 non-root·securityContext 만 적용, PSS 라벨·NetworkPolicy 매니페스트 없음) |
| 데이터 | 저장 암호화 | KMS(RDS, ElastiCache, EBS, ECR), GCP CMEK(Cloud SQL) |
| 데이터 | 전송 암호화 | TLS 1.2+, RDS `rds.force_ssl=1`, ElastiCache 전송 암호화, Cloud SQL SSL 필수, 논리 복제 접속 `sslmode=require` |
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
| `core-service-app` | Pod Identity | S3 특정 prefix |

## 3. DB 계정 분리

| 계정 | 위치 | 권한 |
|---|---|---|
| `app_rw` | RDS | 앱 스키마 DML **+ Flyway DDL** (현재 Flyway 가 `app_rw` 로 실행돼 스키마·테이블 소유자가 된다 → `CREATE ON DATABASE`, PostgreSQL 15+ 는 `CREATE ON SCHEMA public` 도 필요). 원장 UPDATE/DELETE 를 DB 권한으로 막으려면 마이그레이션 계정과 분리해야 한다 |
| `dr_replicator` | RDS | `rds_replication`, 복제 대상 테이블 SELECT. Cloud SQL 구독이 이 계정으로 접속 (ADR-0020) |
| 구독 소유 계정 | Cloud SQL | `dr_subscription` 을 만든 관리 계정. 평시 쓰기는 구독 apply 뿐. 필요한 권한(`cloudsqlsuperuser` / `pg_create_subscription`)은 공식 문서 확인 필요 |
| `app_rw` | Cloud SQL | **평시 NOLOGIN → Failover 시 LOGIN 전환** |

## 4. 보안 점검 체크리스트
- [ ] 퍼블릭 S3 버킷 0개
- [ ] 0.0.0.0/0 Inbound SG는 ALB 443만 (도메인·ACM 전에는 ALB 80 을 허용 CIDR 로만 개방)
- [ ] IAM Access Key 0개 (CI 포함)
- [ ] checkov High 이상 0건 또는 예외 사유 문서화
- [ ] 컨테이너 root 실행 0개
