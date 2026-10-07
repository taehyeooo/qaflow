#!/usr/bin/env bash
# 서비스별 설정: ~/.config/qaflow/<origin 레포 이름>.json (QAFLOW_CONFIG로 바꿀 수 있음).
# 스크립트에는 특정 서비스의 테이블·API·경로를 넣지 않는다 — 전부 이 설정에서 받는다.
qaflow_config() {
  if [ -n "${QAFLOW_CONFIG:-}" ]; then echo "$QAFLOW_CONFIG"; return; fi
  local url name; url=$(git remote get-url origin 2>/dev/null || true); name=$(basename "${url%.git}")
  [ -z "$name" ] && name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  echo "$HOME/.config/qaflow/$name.json"
}
init_config() {
  export QAFLOW_CONFIG="$(qaflow_config)"
  [ -f "$QAFLOW_CONFIG" ] || { echo "qaflow 설정이 없습니다: $QAFLOW_CONFIG (examples/config.example.json 참고)" >&2; exit 1; }
}
cfg() { local v; v=$(jq -r "$1 // empty" "$QAFLOW_CONFIG"); echo "${v:-${2:-}}"; }
expand() { eval echo "$1"; }
STATE="$HOME/.config/qaflow/state"; mkdir -p "$STATE"
log() { echo "$(date '+%F %T')	$1	${2:-}" >> "$HOME/.config/qaflow/usage.log"; }
# SQL 실행: 설정의 db.cmd 뒤에 SQL을 인자로 붙여 실행(결과를 출력하는 명령이면 DB 종류와 상관없음)
sql() { bash -c "$(cfg .db.cmd) \"\$1\"" _ "$1"; }
