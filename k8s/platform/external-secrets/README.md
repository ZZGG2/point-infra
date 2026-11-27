# External Secrets Operator

| 환경 | SecretStore | 소스 |
|---|---|---|
| aws | `ClusterSecretStore/aws-sm` | AWS Secrets Manager (Pod Identity) |
| gcp-dr | `ClusterSecretStore/gcp-sm` | GCP Secret Manager (Workload Identity) |

동일한 `ExternalSecret` 이름(`core-service-db`)을 양쪽에서 생성 → 앱 매니페스트는 환경과 무관.
TODO: ClusterSecretStore, ExternalSecret 매니페스트 작성

`core-service-db` Secret 에 담을 키 (양쪽 클라우드에 **같은 값**):

| 키 | 용도 |
|---|---|
| `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` | DB 접속 |
| `JWT_PRIVATE_KEY` | access token 서명 — 같은 키여야 Failover 후에도 기존 토큰이 유효 |

event-service 용 Secret (이름 예: `event-secrets`, aws 만 — DR 에는 event-service 없음):

| 키 | 용도 |
|---|---|
| `JWT_PUBLIC_KEY` | access token 검증 (X.509 PEM, `JWT_PRIVATE_KEY` 와 같은 쌍). **없으면 aws 프로필에서 기동 실패** (`JWT_JWK_SET_URI` 도 없을 때). 현재 `k8s/base/event-service` 에 `secretRef` 없음 → 추가 필요 |
| `ADMIN_API_TOKEN` | 이벤트 생성 API(`POST /api/events/admin/{id}`)의 `X-Admin-Token`. 없으면 생성 API 가 항상 403 (기동은 된다). 충분히 긴 랜덤 값 |

- ExternalSecret 의 `dataFrom.extract` 로 JSON 키를 그대로 펼친다. 값 확인은 해시 비교로 (평문 출력 금지).
