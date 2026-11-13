.PHONY: load-test tf-fmt tf-plan-main sync-ai-rules

load-test:
	k6 run load-test/k6/s2-event-spike.js

tf-fmt:
	terraform fmt -recursive infra/terraform

tf-plan-main:
	cd infra/terraform/envs/aws-main && terraform init && terraform plan

# 공통 AI 규칙을 형제 레포(../point-backend, ../point-frontend)에 동기화
sync-ai-rules:
	./scripts/sync-ai-rules.sh
