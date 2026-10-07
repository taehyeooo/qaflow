---
name: qa-data
description: QA로 생긴 테스트 데이터를 자동으로 정리한다 — QA 전 테이블별 마지막 id·개수를 저장하고, QA 뒤 그 이후 생긴 테스트 계정 행만 정해진 순서로 지운 뒤 개수가 같은지 확인한다. QA 시작 전과 끝에 반드시 쓴다.
---

# 테스트 데이터 정리 (qaflow)

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/data.sh" snapshot | cleanup [--dry-run] | check`

- 지우는 대상 = 설정 `data.tables`의 각 테이블에서 **테스트 계정 조건(owner) + 기준 id보다 큰 행**뿐이다. owner가 빈 테이블이 있으면 아무것도 하지 않고 멈춘다.
- 처음 쓰는 서비스는 `cleanup --dry-run`으로 무엇이 지워질지 먼저 보여 준다.
- `check`가 "다름"이면 무엇이 남았는지 사용자에게 알리고(새 테이블이 설정에 없을 수 있음) 설정에 추가한다.
- 운영 DB에는 쓰지 않는다(설정의 db.cmd는 개발·테스트 DB만).
