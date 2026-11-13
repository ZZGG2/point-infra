# k8s/argocd/aws

EKS 의 ArgoCD 가 `root-aws` Application 으로 이 폴더를 동기화한다 (AppProject, Sync Window).

애드온·앱 Application(aws-load-balancer-controller, external-secrets, keda, platform-*, apps-aws)은
ECR 주소·VPC ID 같은 환경 값을 공개 저장소에 두지 않기 위해 Terraform `modules/aws/argocd-bootstrap` 이
값을 주입해 등록한다. 매니페스트 본문은 `k8s/overlays`, `k8s/platform` 과 공식 Helm 차트에 있다.
