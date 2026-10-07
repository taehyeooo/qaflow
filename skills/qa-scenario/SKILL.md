---
name: qa-scenario
description: 자주 하는 QA 흐름(예: 공유 → 처리 완료 대기 → 결과 화면 → 저장)을 시나리오 파일로 적어 두고 한 줄로 재생한다 — 단계마다 걸린 시간과 캡처를 남기고 한 장으로 붙인다. 같은 흐름을 두 번 이상 확인할 때, 배포 전후 회귀 확인에 쓴다.
---

# QA 시나리오 (qaflow)

- 목록: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/scenario.sh" list` · 실행: `scenario.sh run <이름>`
- 시나리오 파일: 설정의 `scenarioDir`(기본 `~/.config/qaflow/scenarios/<설정 이름>/<이름>.json`). 형식은 `examples/scenarios/` 참고.
- 비동기 처리(분석·초안 생성 등)는 고정 대기 대신 `wait-sql`로 DB 상태를 기다린다 — 빠르면 빨리 넘어가고, 시간 초과면 실패로 멈춘다.
- 새 시나리오를 만들 때: 손으로 한 번 진행하며 좌표를 캡처로 확인한 뒤 파일로 적는다(좌표는 기기마다 다르니 기기 이름을 description에).
- 실행 후 캡처 묶음 이미지를 읽어 단계마다 기대한 화면인지 확인하고, 실패한 단계·시간을 보고한다. 끝나면 `qa-data cleanup`.
