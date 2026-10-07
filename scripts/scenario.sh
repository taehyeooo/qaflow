#!/usr/bin/env bash
# QA 시나리오 재생: 시나리오 파일(JSON)의 단계를 차례로 실행하고 단계마다 시간·캡처를 남긴 뒤 한 장으로 붙인다.
#   scenario.sh run <시나리오 이름|경로>      list
# 시나리오 위치: 설정 "scenarioDir"(기본 ~/.config/qaflow/scenarios/<설정 이름>/). 단계 종류:
#   {"do":"paste","text":…} {"do":"tap","x":…,"y":…,"name":…} {"do":"shot","name":…} {"do":"wait","seconds":…}
#   {"do":"wait-sql","sql":…,"match":"정규식","timeout":초,"name":…}  — 비동기 처리(분석·초안 등)가 끝나길 기다림
#   {"do":"text","size":…} {"do":"background"} {"do":"foreground","name":…} {"do":"note","text":…}
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
SDIR=$(expand "$(cfg .scenarioDir "$HOME/.config/qaflow/scenarios/$(basename "$QAFLOW_CONFIG" .json)")")
ENV="$DIR/env.sh"
case "${1:-}" in
list) ls "$SDIR" 2>/dev/null | sed 's/\.json$//' ;;
run)
  f=${2:?시나리오}; [ -f "$f" ] || f="$SDIR/$f.json"; [ -f "$f" ] || { echo "시나리오가 없습니다: $f" >&2; exit 1; }
  name=$(jq -r '.name // "scenario"' "$f"); run_id="$(date +%m%d-%H%M%S)-$name"
  RUNS="$HOME/.config/qaflow/runs"; mkdir -p "$RUNS"; steps="[]"; shots=(); t_all=$(date +%s); failed=0
  echo "시나리오: $name ($(jq '.steps | length' "$f")단계)"
  while IFS= read -r st; do
    kind=$(jq -r .do <<< "$st"); label=$(jq -r '.name // .do' <<< "$st"); t0=$(date +%s); shot=""; result="ok"
    case "$kind" in
      paste) bash "$ENV" paste "$(jq -r .text <<< "$st")" >/dev/null ;;
      tap) shot=$(bash "$ENV" tap "$(jq -r .x <<< "$st")" "$(jq -r .y <<< "$st")" "$label" | tail -1) ;;
      shot) shot=$(bash "$ENV" shot "$label") ;;
      foreground) shot=$(bash "$ENV" foreground | tail -1) ;;
      background) bash "$ENV" background >/dev/null ;;
      text) shot=$(bash "$ENV" text "$(jq -r .size <<< "$st")" | tail -1) ;;
      wait) sleep "$(jq -r .seconds <<< "$st")" ;;
      note) result=$(jq -r .text <<< "$st") ;;
      wait-sql)
        q=$(jq -r .sql <<< "$st"); m=$(jq -r .match <<< "$st"); to=$(jq -r '.timeout // 180' <<< "$st")
        until out=$(sql "$q") && printf '%s' "$out" | grep -Eq "$m"; do
          sleep 3; [ $(( $(date +%s) - t0 )) -gt "$to" ] && { result="시간 초과(${to}초): $out"; failed=1; break; }
        done
        [ "$result" = ok ] && result=$(printf '%s' "$out" | head -1) ;;
      *) result="모르는 단계: $kind"; failed=1 ;;
    esac
    secs=$(( $(date +%s) - t0 ))
    printf ' %-10s %-18s %3s초  %s\n' "$kind" "$label" "$secs" "$result"
    steps=$(jq -c --arg k "$kind" --arg l "$label" --argjson s "$secs" --arg shot "$shot" --arg r "$result" '. + [{do:$k, name:$l, seconds:$s, shot:$shot, result:$r}]' <<< "$steps")
    [ -n "$shot" ] && shots+=("$label (${secs}초)" "$shot")
    [ "$failed" = 1 ] && break
  done < <(jq -c '.steps[]' "$f")
  total=$(( $(date +%s) - t_all ))
  sheet=""; [ ${#shots[@]} -gt 0 ] && sheet=$(python3 "$DIR/sheet.py" "$RUNS/$run_id.png" "$(cfg .sheetColumns 4)" "${shots[@]}" | tail -1)
  jq -n --arg id "$run_id" --arg name "$name" --arg at "$(date '+%F %T')" --argjson total "$total" --argjson failed "$failed" \
     --arg sheet "$sheet" --argjson steps "$steps" '{id:$id, name:$name, at:$at, totalSeconds:$total, failed:($failed==1), sheet:$sheet, steps:$steps}' > "$RUNS/$run_id.json"
  log scenario "$name ${total}s failed=$failed"
  echo "끝: 전체 ${total}초 · 기록 $RUNS/$run_id.json · 캡처 묶음 ${sheet:-없음}"
  exit $failed ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
