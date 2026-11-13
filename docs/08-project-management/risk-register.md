# 리스크 관리

| ID | 리스크 | 가능성 | 영향 | 대응 |
|---|---|---|---|---|
| R1 | 클라우드 비용 초과 (MSK, RDS, NAT, EKS 상시) | 높음 | 높음 | 예산 알림, 비작업 시 destroy, MSK Serverless 대체안, 일 비용 확인 |
| R2 | HA VPN + Cloud SQL Private IP 라우팅 실패 | 중간 | 높음 | Phase 4 초반 PoC 우선 수행, 실패 시 Cloud SQL Public IP + 허용 IP + SSL로 임시 대체 (문서화) |
| R3 | Debezium JDBC Sink 타입/DDL 호환 문제 | 중간 | 중간 | 복제 대상 테이블 최소화, 단순 타입 사용, Flyway 양쪽 적용 |
| R4 | GKE 생성 시간이 길어 RTO 초과 | 중간 | 중간 | 측정 후 컨트롤 플레인 상시 옵션 적용 (ADR 갱신) |
| R5 | Spot 용량 부족으로 이벤트 확장 실패 | 낮음 | 높음 | 인스턴스 패밀리 다양화, On-Demand fallback |
| R6 | EKS 서브넷 IP 고갈 | 낮음 | 높음 | /19 서브넷, Prefix Delegation |
| R7 | 범위 과다로 일정 지연 | 높음 | 중간 | 기능 우선순위 P0만 MVP, Phase 6 항목은 선택 |
| R8 | 시크릿/키 GitHub 노출 | 낮음 | 높음 | OIDC, gitleaks pre-commit, .gitignore |
| R9 | Replication Slot 미소비로 RDS 스토리지 폭증 | 중간 | 중간 | 커넥터 정지 시 알람, 훈련 후 slot 정리 절차 |
