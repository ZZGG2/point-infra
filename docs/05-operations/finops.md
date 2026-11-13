# FinOps — 비용 모델과 절감 전략

> 금액은 설계 단계 추정치이며, 구축 후 Cost Explorer 실측값으로 갱신한다. 리전·시점별 단가는 AWS/GCP 가격 계산기로 재확인할 것.

## 1. 비용 구조 원칙

| 구분 | 평시 | 이벤트 시 | DR 시 |
|---|---|---|---|
| monolith 컴퓨팅 | On-Demand 고정 (소형 2대) | 동일 | GKE 소형 노드풀 |
| event 컴퓨팅 | 0~1 노드 | Karpenter Spot 확장 | **0 (배포 안 함)** |
| DB | Aurora | 동일 | Cloud SQL (이미 존재) |
| DR 상시 비용 | Cloud SQL + VPN + Static IP | 동일 | + GKE |

## 2. DR 전략별 비용 비교 (산정 틀)

| 항목 | Active-Active | Warm Standby | **Pilot Light (채택)** |
|---|---|---|---|
| DR 컴퓨팅 | Main과 동일 | 축소 클러스터 상시 | **0** |
| DR DB | 동일 사양 | 축소 사양 | 축소 사양 |
| DR 캐시/Kafka | 필요 | 필요 | **불필요** (선택적 복구) |
| 데이터 동기화 | 양방향 (충돌 해결) | 단방향 | 단방향 |
| 월 DR 비용 (상대) | ~100% | ~30~50% | **~10~20%** |
| RTO | ~0 | 수 분 | ≤ 30분 |

→ 실측 후 `월 $` 값으로 표를 채워 포트폴리오에 첨부.

## 3. 절감 레버

| 레버 | 적용 | 기대 효과 |
|---|---|---|
| Karpenter Spot + 다양한 인스턴스 패밀리 | event NodePool | On-Demand 대비 큰 폭 절감, 회수 시 재배치 |
| Consolidation | Karpenter `consolidationPolicy: WhenEmptyOrUnderutilized` | 이벤트 후 노드 자동 회수 |
| KEDA Cron 사전 확장 | 이벤트 시간에만 확장 | 상시 대기 레플리카 제거 |
| VPC Endpoint | ECR/S3 트래픽 | NAT 처리 비용 절감 |
| NAT Gateway 1개 (학습 환경) | Public subnet 1곳 | NAT 고정비 절감 (가용성 트레이드오프 문서화) |
| Graviton (ARM) | monolith 노드 | 동일 성능 대비 비용 절감 (멀티아키 이미지 필요) |
| 학습 기간 destroy | aws-main 비작업 시간 | 실습 비용 최소화 |
| MSK Serverless / Strimzi | Kafka | Provisioned 대비 소규모 환경 절감 |

## 4. 태깅 정책 (비용 배분)

| 태그 | 예시 |
|---|---|
| `project` | point-platform |
| `env` | main / dr-standby / dr-compute |
| `component` | monolith / event / data / network |
| `cost-center` | portfolio |

## 5. 측정 계획
- [ ] 평시 1주 비용 (이벤트 없음)
- [ ] 이벤트 1회(부하 테스트) 추가 비용
- [ ] DR 훈련 1회(GKE 1시간) 추가 비용
- [ ] "1:1 Active-Active였다면" 시뮬레이션 비용 → 절감률 계산
