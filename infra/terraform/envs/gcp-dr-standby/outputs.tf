# gcp-dr-compute 가 참조할 값 (network self_link, subnet, cloudsql private ip, static ip 등)
output "artifact_registry" { value = google_artifact_registry_repository.apps.id }
