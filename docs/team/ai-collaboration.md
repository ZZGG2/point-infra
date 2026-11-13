# AI 협업 가이드

> 팀원 모두 AI를 쓴다. AI끼리 서로 다른 결정을 내려 코드가 충돌하지 않도록 **같은 지침을, 같은 방식으로** 전달한다.

## 1. 구조 — 원본 1개, 배포 N개

```
point-infra/team/ai/AGENTS.common.md   ← 공통 규칙 원본 (여기만 수정)
        │  make sync-ai-rules
        ▼
<각 레포>/AGENTS.md
  ├─ [COMMON 블록]  자동 동기화 — 직접 수정 금지
  └─ [레포별 규칙]  해당 레포에서 PR로 수정
<각 레포>/CLAUDE.md                     → @AGENTS.md (import)
<각 레포>/GEMINI.md                     → AGENTS.md 참조
<각 레포>/.github/copilot-instructions.md → AGENTS.md 참조 + 핵심 요약
```

| 도구 | 읽는 파일 | 비고 |
|---|---|---|
| Claude Code | `CLAUDE.md` → `AGENTS.md` | 개인 설정은 `CLAUDE.local.md` (gitignore) |
| Cursor | `AGENTS.md` | 개인 규칙은 User Rules에, 레포 `.cursor/rules` 추가는 PR 필요 |
| GitHub Copilot | `.github/copilot-instructions.md`, `AGENTS.md` | |
| Gemini CLI | `GEMINI.md` | |
| ChatGPT / Claude 웹 등 대화형 | 자동 인식 없음 | [session-prompt.md](../../team/ai/session-prompt.md)를 대화 시작 시 붙여넣기 |

> 도구별 지원 범위는 바뀔 수 있으므로, 새 도구 도입 시 해당 도구가 AGENTS.md를 읽는지 확인하고 이 표를 갱신한다.

## 2. 개인 설정과 팀 규칙의 관계

- 개인 AI 설정(말투, 설명 길이 등)은 자유. 단 **팀 규칙과 충돌하는 개인 규칙 금지** (예: "테스트 생략", "다른 프레임워크 사용").
- 레포에 커밋되는 AI 설정 파일은 위 표의 파일뿐. 그 외(`.cursor/`, `.claude/settings.json` 등) 추가는 PR + 합의.

## 3. AI에게 작업을 시킬 때 — 프롬프트 템플릿

```text
[이슈] #42 퀴즈 선착순 Lua 스크립트 구현
[레포/범위] point-backend / event-service/src/main/.../quiz/, resources/scripts/ 만 수정
[참고 문서] AGENTS.md, point-infra docs/02-adr/0007-redis-queue-and-dedup.md
[요구사항]
 - 중복 참여 -1, 낙첨 0, 당첨 1 반환
 - 동시 요청 100건 테스트 포함
[하지 말 것] build.gradle 수정, common 패키지 수정
[출력] 변경 파일 목록 + 가정한 내용 + 남은 TODO
```

**핵심은 `[레포/범위]`와 `[하지 말 것]`.** 범위를 주지 않으면 AI가 "하는 김에" 다른 파일을 고쳐 충돌을 만든다.

## 4. AI 결과물 검증 체크리스트 (PR 올리기 전)

- [ ] 변경 파일이 이슈 범위 안에만 있다 (`git diff --stat` 확인)
- [ ] 의존성·설정 파일이 바뀌지 않았다
- [ ] 존재하지 않는 API/옵션/Terraform 속성이 없다 (공식 문서로 확인)
- [ ] 테스트를 직접 실행해 통과했다 (AI가 "통과했다"고 한 말은 근거가 아님)
- [ ] 시크릿·계정 ID·실제 도메인이 없다
- [ ] 모든 줄을 설명할 수 있다
- [ ] PR 템플릿 "AI 사용" 항목 체크, 주요 프롬프트 요약 첨부(선택)

## 5. 자주 생기는 AI 충돌 패턴과 예방

| 패턴 | 예시 | 예방 규칙 (AGENTS.md) |
|---|---|---|
| 기술 대체 제안 | "Lambda가 더 낫습니다" → 구현 | Decision Lock §2 |
| 스타일 드리프트 | 팀원 A의 AI는 record DTO, B의 AI는 Lombok | 기존 패턴 따르기 §3-5 |
| 의존성 난립 | 각자 AI가 다른 유틸 라이브러리 추가 | 의존성 추가 금지 §3-2 |
| 마이그레이션 번호 충돌 | 둘 다 `V3__` 생성 | 타임스탬프 버전 (backend 규칙) |
| 생성 타입 vs 수기 타입 | 프론트 AI가 API 타입을 손으로 작성 | OpenAPI 생성 타입만 (frontend 규칙) |
| 무단 리팩터링 | 버그 수정 PR에 전체 포맷 변경 섞임 | 한 PR 한 목적 §3-3 |
| 테스트 무력화 | 실패 테스트 skip | Hard Stop §4 |

## 6. 규칙 변경 절차

1. AI가 반복적으로 같은 실수를 하면 → 이슈 생성 (`type:chore`, `ai-rules`)
2. `team/ai/AGENTS.common.md` 수정, 버전 올림 (규칙 추가 = minor, 문구 수정 = patch, 기존 규칙 반대로 변경 = major)
3. PR 리뷰 **팀원 과반 승인**
4. 머지 후 `make sync-ai-rules` → 각 레포에 `chore(ai): sync common rules vX.Y.Z` PR
