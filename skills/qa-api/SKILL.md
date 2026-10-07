---
name: qa-api
description: 정해 둔 API를 차례로 불러 응답 코드와 응답 내용 조건을 확인한다(스모크 테스트). 배포 전 로컬, 배포 후 운영(인증 없는 확인만), 큰 백엔드 변경 뒤에 쓴다.
---

# API 스모크 (qaflow)

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/api.sh" [묶음 이름]` — 묶음은 설정 `api.suites`.
- `auth: "token"` 묶음은 테스트 토큰을 자동으로 새로 만들어 쓴다(개발·로컬 전용).
- 운영 묶음은 `auth: "none"`으로 인증 없는 확인(헬스, 401 등)만 둔다 — 운영용 토큰을 만들지 않는다.
- 새 API를 만들면 그 API의 확인 한 줄(코드 + jq 조건)을 묶음에 추가한다.
