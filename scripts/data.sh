#!/usr/bin/env bash
# 테스트 데이터 자동 정리: QA 전에 테스트 계정 데이터의 테이블별 마지막 id·개수를 기억하고,
# QA 뒤에는 그 이후 생긴 행만(테스트 계정 조건 + id > 기억한 값) 설정한 순서대로 지운 뒤 개수가 같은지 확인한다.
#   data.sh snapshot          기준 저장
#   data.sh cleanup [--dry-run]  기준 이후 생긴 테스트 데이터 삭제(미리보기 가능) → 개수 비교
#   data.sh check             지금 개수가 기준과 같은지
# 설정 "data.tables": [{ "name": 테이블, "owner": 테스트 계정 데이터만 고르는 SQL 조건 }] — 지우는 순서(자식 → 부모)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
SNAP="$STATE/data-$(basename "$QAFLOW_CONFIG" .json).json"
ID=$(cfg .data.idColumn id)
num() { printf '%s' "$1" | grep -oE '[0-9]+' | head -1; }
tables() { jq -r '.data.tables[] | [.name, .owner] | @tsv' "$QAFLOW_CONFIG"; }
counts() { local out=""; while IFS=$'\t' read -r t o; do out+="$t=$(num "$(sql "select count(*) from $t where $o")") "; done < <(tables); echo "${out% }"; }
while IFS=$'\t' read -r t o; do [ -n "$o" ] || { echo "테이블 $t 에 테스트 계정 조건(owner)이 없습니다 — 안전을 위해 멈춥니다" >&2; exit 1; }; done < <(tables)

case "${1:-}" in
snapshot)
  json="{}"
  while IFS=$'\t' read -r t o; do
    m=$(num "$(sql "select coalesce(max($ID), 0) from $t where $o")"); json=$(jq -c --arg t "$t" --argjson m "${m:-0}" '.[$t]=$m' <<< "$json")
  done < <(tables)
  c=$(counts); jq -n --argjson max "$json" --arg counts "$c" --arg at "$(date '+%F %T')" '{at:$at, max:$max, counts:$counts}' > "$SNAP"
  log data-snapshot "$c"; echo "기준 저장: $c" ;;
cleanup)
  [ -f "$SNAP" ] || { echo "기준이 없습니다 — 먼저 data.sh snapshot" >&2; exit 1; }
  DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1
  total=0
  while IFS=$'\t' read -r t o; do
    base=$(jq -r --arg t "$t" '.max[$t] // 0' "$SNAP"); cond="($o) and $ID > $base"
    n=$(num "$(sql "select count(*) from $t where $cond")"); n=${n:-0}
    if [ "$n" -gt 0 ]; then
      if [ "$DRY" = 1 ]; then echo " - $t: ${n}행 지울 예정 ($ID > $base)"; else sql "delete from $t where $cond" >/dev/null; echo " - $t: ${n}행 삭제"; fi
      total=$((total + n))
    fi
  done < <(tables)
  [ "$DRY" = 1 ] && { echo "미리보기: 모두 ${total}행"; exit 0; }
  log data-cleanup "${total}행"; echo "정리: 모두 ${total}행"
  chk=$("$0" check 2>&1) && st=ok || st=fail; echo "$chk" | grep -v '^리포트' || true
  echo "리포트: $(jq -n --arg t "$total" --arg chk "$chk" --arg st "$st" --arg snap "$(jq -r .counts "$SNAP")" --arg env "$(cfg .label "")" '
    {plugin:"qaflow", kind:"data-cleanup", title:"테스트 데이터 정리", summary:"QA로 생긴 \($t)행 삭제 · \($chk)", env:$env, status:$st,
     sections:[{heading:"기준(QA 전)", text:$snap},{heading:"비교", text:$chk}]}' | report)" ;;
check)
  [ -f "$SNAP" ] || { echo "기준이 없습니다" >&2; exit 1; }
  before=$(jq -r .counts "$SNAP"); now=$(counts)
  if [ "$before" = "$now" ]; then log data-ok "$now"; echo "같음: $now"; else log data-diff "$before -> $now"; echo "다름: 기준 $before / 지금 $now"; exit 1; fi ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
