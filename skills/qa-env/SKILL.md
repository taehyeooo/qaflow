---
name: qa-env
description: 모바일 앱 QA 환경을 준비/원복한다 — 테스트 토큰 갱신, 임시 토큰 패치, 로컬 서버를 보는 번들러, 앱 재실행, 탭·캡처·글자 크기·백그라운드 전환, 외부 API 사용량. "시뮬레이터로 보여줘", "QA 진행해줘"의 시작과 끝에 쓴다.
---

# QA 환경 (qaflow)

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/env.sh" <명령>` — 설정을 찾을 수 있는 레포 폴더에서 실행.

1. 외부 AI API를 쓰는 흐름이면 `quota`로 오늘 사용량을 먼저 알린다.
2. `qa-data`의 `snapshot`으로 데이터 기준을 저장한다.
3. `start`(토큰이 오래됐으면 새로 만들고 시작) → 창이 여러 개면 `front`.
4. 진행: `tap X Y 이름`, `paste 텍스트`, `shot 이름`, `text 크기`, `background`/`foreground` — 반복되는 흐름은 `qa-scenario`로.
5. 끝: `qa-data cleanup` → `stop`(QA 한 번의 시간·탭 수가 기록되고, 남은 패치 0건 확인).

지킬 것: 임시 토큰 패치는 커밋하지 않는다. 사용자 실제 계정 기기는 쓰지 않는다. 결과를 말할 때 실행 환경(설정의 label)을 밝힌다.
