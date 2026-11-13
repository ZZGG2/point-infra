# External Secrets Operator

| 환경 | SecretStore | 소스 |
|---|---|---|
| aws | `ClusterSecretStore/aws-sm` | AWS Secrets Manager (Pod Identity) |
| gcp-dr | `ClusterSecretStore/gcp-sm` | GCP Secret Manager (Workload Identity) |

동일한 `ExternalSecret` 이름(`monolith-db`)을 양쪽에서 생성 → 앱 매니페스트는 환경과 무관.
TODO: ClusterSecretStore, ExternalSecret 매니페스트 작성
