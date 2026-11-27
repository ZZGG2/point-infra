# 리스크 관리

| ID | 리스크 | 가능성 | 영향 | 대응 |
|---|---|---|---|---|
| R1 | 클라우드 비용 초과 (RDS, NAT, EKS 상시) | 높음 | 높음 | 예산 알림, 비작업 시 destroy, 일 비용 확인 |
| R2 | HA VPN + Cloud SQL Private IP 라우팅 실패 | 중간 | 높음 | Phase 4 초반 PoC 우선 수행, 실패 시 Cloud SQL Public IP + 허용 IP + SSL로 임시 대체 (문서화) |
| R3 | Cloud SQL 의 네이티브 `CREATE SUBSCRIPTION` 권한·제약 미확인 | 중간 | 높음 | Phase 4 초반 PoC 로 확인. 안 되면 pglogical 확장 (ADR-0020 대안 B). DDL 미복제 → Flyway 양쪽 적용 |
| R4 | GKE 생성 시간이 길어 RTO 초과 | 중간 | 중간 | 측정 후 컨트롤 플레인 상시 옵션 적용 (ADR 갱신) |
| R5 | Spot 용량 부족으로 이벤트 확장 실패 | 낮음 | 높음 | 인스턴스 패밀리 다양화, On-Demand fallback |
| R6 | EKS 서브넷 IP 고갈 | 낮음 | 높음 | /19 서브넷, Prefix Delegation |
| R7 | 범위 과다로 일정 지연 | 높음 | 중간 | 기능 우선순위 P0만 MVP, Phase 6 항목은 선택 |
| R8 | 시크릿/키 GitHub 노출 | 낮음 | 높음 | OIDC, gitleaks pre-commit, .gitignore |
| R9 | Replication Slot 미소비로 RDS 스토리지 폭증 | 중간 | 중간 | `max_slot_wal_keep_size` 상한, 구독 정지·slot lag 알람, Failover·드릴 후 slot 정리 절차 |
| R10 | 원장 반영 Stream 유실 (ElastiCache 장애 조치 시 비동기 복제로 마지막 쓰기 유실, 메모리 부족) | 낮음 | 높음 | Multi-AZ + 자동 장애 조치, 필요 시 `WAIT`, 메모리 알람, 이벤트 후 당첨자 Set ↔ 원장 대사 (ADR-0019) |
