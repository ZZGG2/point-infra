# ADR-0021: Spring Boot 3.5 → 4.1 업그레이드
- 상태: **Accepted** (승인: 2026-11-26 KST, #41)
- 날짜: 2026-11-26 KST
- 대체: 없음 (AGENTS 공통 규칙 Decision Lock "언어/버전"의 `Spring Boot 3.x` 를 `4.x` 로 바꾼다)
- 관련: point-backend #10 (CI Trivy CRITICAL), #11 (tomcat·netty 패치)
- 논의: #41

## 맥락
- backend main CI 의 Trivy 스캔이 CRITICAL 로 실패해 이미지 push 가 막혀 있다 (point-backend #10).
- tomcat·netty 는 3.5 계열 안에서 패치했다 (#11). 남은 spring-webmvc 2건(CVE-2026-47884, 47890)은
  **Spring Framework 7.0.9 이상에서만** 고쳐졌다. 3.5 계열 최신(3.5.16)은 6.2.19 를 쓰고, 6.2 에는 패치가 없다.
- 3.5 에 머무르면 앞으로 나올 Framework CVE 도 같은 상황이 반복된다 (`.trivyignore` 예외가 쌓인다).
- tomcat·netty 버전을 `ext` 로 직접 덮어쓰는 지금 방식은 BOM 이 검증한 조합에서 벗어난다.

## 결정
**point-backend 를 Spring Boot 4.1.x(작성 시점 4.1.3)로 올린다.**

| 항목 | 3.5.16 (지금) | 4.1.3 |
|---|---|---|
| Spring Framework | 6.2.19 | 7.0.11 (CVE 2건 해결) |
| Tomcat | 10.1.62 (`ext` 덮어씀) | 11.0.27 (BOM 관리 → `ext` 제거) |
| Netty / Lettuce | 4.1.141 (`ext`) / 6.x | 4.2.20 / 7.5.2 |
| Jackson | 2.x | 3.x (패키지 `tools.jackson`) |
| Testcontainers | 1.21.4 (`ext`) | 2.0.5 (BOM 관리 → `ext` 제거) |
| Java | 21 | 21 (변경 없음) |

- 4.2.0 이 아니라 4.1.x 를 고른 이유: 4.2 는 막 나온 .0 이고, 4.1 은 패치가 여러 번 나와 안정됐다.
- Decision Lock "언어/버전"을 `Spring Boot 4.x` 로 바꾸고 공통 규칙 버전을 올린다 (v1.5.0).
- 업그레이드 PR 이 머지되면 `.trivyignore` 의 spring-webmvc 예외는 필요 없다 (만들었다면 같이 지운다).

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| **A. Boot 4.1 업그레이드** | CVE 근본 해결, BOM 이 관리하는 조합으로 복귀, 지원 기간 확보 | 메이저 마이그레이션 (아래 후속 과제) | **채택** |
| B. 3.5 유지 + `.trivyignore` | 변경 최소 | 예외가 계속 쌓임, 만료일마다 재검토 | 임시 조치일 뿐 |
| C. 3.5 유지 + Framework 만 7.x 로 덮어쓰기 | 변경 적어 보임 | Boot 3.5 는 Framework 7 을 지원하지 않는다 → 자동 설정이 깨짐 | 지원되지 않는 조합 |
| D. Boot 4.2.0 | 가장 최신 | .0 릴리스, 안정성 미검증 | 4.1 의 다음 패치 시점에 재검토 |

## 결과
- 긍정: spring-webmvc CRITICAL 해결, `ext` 덮어쓰기 3줄 제거, 이후 보안 패치를 BOM 만 올려 받는다.
- 부정: 메이저 변경이라 한 번에 고칠 곳이 많다. 팀원 진행 중 브랜치와 충돌 가능.
- 후속 과제 (point-backend 업그레이드 PR 에서, 구현 시 공식 마이그레이션 가이드로 확인):
  - 스타터 모듈 분리 — 이름이 바뀐 스타터(web, flyway, data-redis 등)와 테스트 스타터 정리
  - Jackson 3 — `com.fasterxml.jackson` import 변경, 직렬화 동작 차이(날짜 등) 테스트
  - Testcontainers 2 — 아티팩트 이름·패키지 변경
  - Lettuce 7 / Spring Data Redis 4 — Stream API(`XREADGROUP`, `XCLAIM`) 동작 확인
  - Actuator·Micrometer 설정 키 변경 확인, OpenAPI 계약 변화 없음 확인
  - point-infra: AGENTS 공통 규칙 v1.5.0 동기화, `team/ai/session-prompt.md` 의 "Spring Boot 3" 수정
