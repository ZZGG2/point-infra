# ADR-0016: DR DNS 전환을 AWS 컨트롤 플레인 없이 수행
- 상태: Proposed · 날짜: 2026-11-13
- 관련: ADR-0010 (DR 독립성) 의 DNS 항목 재검토, ADR-0011 (승인 기반 Failover)

## 맥락
- ADR-0010 은 DNS 를 "Route 53 유지 + 장애 시 **도메인 등록기관에서 NS 변경**" 으로 정했다. 그러나 TLD 의 NS 레코드 TTL 은 보통 24~48시간이라 RTO 30분 안에 전환이 끝나지 않는다.
- `scripts/dr/switch-dns.sh` 는 `aws route53 update-health-check --inverted` 로 전환하도록 계획돼 있다. 이는 AWS 자격 증명과 Route 53 **컨트롤 플레인**(us-east-1)이 필요해 "DR 경로에서 AWS 리소스 참조 금지"(ADR-0010)와 충돌하고, `dr-failover.yml` 은 GCP 인증만 수행한다.
- Route 53 의 **데이터 플레인**(DNS 응답, Health Check 판정)은 전 세계에 분산돼 있어 서울 리전 장애나 컨트롤 플레인 장애에도 계속 동작한다.

## 결정 (제안)
1. **(A) 서울 리전(`ap-northeast-2`) 단일 리전 장애**: Route 53 Failover 레코드(Primary=AWS ALB, Secondary=GCP Static IP, TTL 60s)를 유지한다. 승인 후 전환은 Primary 의 Health Check 가 **GCP 에 둔 전환 플래그 엔드포인트**를 보게 하고, 워크플로가 GCP 쪽 플래그를 바꿔 Health Check 를 실패시킨다 → AWS API 호출 없이 1~2분 내 전환. (Inverted Health Check API 호출은 AWS 가 정상일 때의 보조 수단)
2. **(B) AWS 글로벌 컨트롤 플레인 장애 대비**: 1번은 데이터 플레인만 쓰므로 그대로 동작한다. 추가로 Route 53 자체 장애까지 대비하려면 AWS 외부의 독립 권한 DNS(예: Cloudflare DNS)를 Primary 로 두거나 Route 53 과 Secondary DNS(Zone Transfer) 를 병행한다.
3. 등록기관 NS 변경은 DR 절차에서 제외한다.

## 고려한 대안
| 대안 | 장점 | 단점 | 기각/보류 이유 |
|---|---|---|---|
| 등록기관 NS 변경 (현행 ADR-0010) | 추가 구성 없음 | TLD TTL 24~48시간 | RTO 미달 |
| Route 53 Health Check Invert API | 구현 단순 | AWS 자격 증명 + 컨트롤 플레인 필요 | ADR-0010 위반 → 보조 수단으로만 |
| **GCP 전환 플래그 + Route 53 Health Check** | AWS API 불필요, 기존 Failover 레코드 재사용 | 플래그 엔드포인트(GCP) 가용성 관리 필요 | **1차 채택 제안** |
| 외부 권한 DNS (Cloudflare 등) 를 앞단에 | Route 53 전체 장애에도 독립 | 도메인·인증서·비용 관리 주체 추가 | 요구 수준에 따라 2차 선택 |

## 결과 (Accepted 시)
- (+) DR 전환 경로에서 AWS 의존 제거 (ADR-0010 일관성)
- (−) 플래그 엔드포인트 운영, Health Check 오판 시 오전환 위험 → 판정 주기·임계값 설계 필요
- 후속: `switch-dns.sh` 교체, ADR-0010 DNS 항목 상태 갱신, dr-runbook §4 확정
