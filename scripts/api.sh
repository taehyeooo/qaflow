#!/usr/bin/env bash
# API 스모크 테스트: 설정의 API를 차례로 불러 응답 코드와(선택) 응답 내용 조건을 확인한다.
#   api.sh [묶음 이름=default]      설정 "api.suites.<이름>": { base, auth: "token"|"none", checks: [...] }
#   check: { name, method, path, body?, expect: 200, jq?: "응답 JSON에 대한 jq 조건(참이면 통과)" }
# 인증이 필요한 묶음은 env.sh token으로 만든 테스트 토큰을 쓴다(운영처럼 토큰을 만들면 안 되는 곳은 auth "none"만).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
S=${1:-default}; P=".api.suites.\"$S\""
jq -e "$P" "$QAFLOW_CONFIG" >/dev/null || { echo "API 묶음이 없습니다: $S" >&2; exit 1; }
BASE=$(cfg "$P.base"); AUTH=$(cfg "$P.auth" none); hdr=()
if [ "$AUTH" = token ]; then
  bash "$DIR/env.sh" token >/dev/null
  TOKEN_FILE=$(expand "$(cfg .env.token.file "$HOME/.config/qaflow/token")"); hdr=(-H "Authorization: Bearer $(cat "$TOKEN_FILE")")
fi
pass=0; fail=0; t0=$(date +%s); tmp=$(mktemp); ROWS="[]"
while IFS= read -r c; do
  name=$(jq -r .name <<< "$c"); method=$(jq -r '.method // "GET"' <<< "$c"); path=$(jq -r .path <<< "$c")
  expect=$(jq -r '.expect // 200' <<< "$c"); cond=$(jq -r '.jq // empty' <<< "$c"); body=$(jq -c '.body // empty' <<< "$c")
  args=(-s -o "$tmp" -w '%{http_code} %{time_total}' -X "$method" ${hdr[@]+"${hdr[@]}"})
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  read -r code time < <(curl "${args[@]}" "$BASE$path" </dev/null)
  ok=1; why=""
  [ "$code" = "$expect" ] || { ok=0; why="코드 $code(기대 $expect)"; }
  if [ "$ok" = 1 ] && [ -n "$cond" ]; then jq -e "$cond" "$tmp" >/dev/null 2>&1 || { ok=0; why="조건 불일치: $cond"; }; fi
  ms=$(awk -v t="$time" 'BEGIN{printf "%d", t*1000}')
  if [ "$ok" = 1 ]; then pass=$((pass+1)); printf ' ✓ %-34s %s %sms\n' "$name" "$code" "$ms"; else fail=$((fail+1)); printf ' ✗ %-34s %s\n' "$name" "$why"; fi
  ROWS=$(jq -c --arg n "$name" --arg m "$method $path" --arg c "$code" --arg ms "$ms" --arg r "$( [ "$ok" = 1 ] && echo 통과 || echo "실패: $why")" '. + [[$n,$m,$c,"\($ms)ms",$r]]' <<< "$ROWS")
done < <(jq -c "$P.checks[]" "$QAFLOW_CONFIG")
rm -f "$tmp"; secs=$(( $(date +%s) - t0 ))
log api "$S pass=$pass fail=$fail ${secs}s"; echo "API $S: 통과 $pass · 실패 $fail · ${secs}초 ($BASE)"
echo "리포트: $(jq -n --argjson rows "$ROWS" --arg s "$S" --arg base "$BASE" --argjson p "$pass" --argjson f "$fail" '
  {plugin:"qaflow", kind:"api", title:"API 확인 — \($s)", summary:"통과 \($p) · 실패 \($f)", env:$base, status:(if $f>0 then "fail" else "ok" end),
   sections:[{heading:"결과", table:{columns:["이름","요청","코드","시간","결과"], rows:$rows}}]}' | report)"
[ "$fail" = 0 ]
