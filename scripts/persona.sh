#!/usr/bin/env bash
# 페르소나 QA: 페르소나마다 [기기 상태 → 데이터 준비 → 로그인 상태 → 시나리오 → 캡처] 를 돌리고 데이터를 원래대로 돌린다.
# 화면 평가(그 사람 입장에서 막힌 곳·불편한 곳)는 Claude가 캡처를 보고 findings로 기록하고, report로 HTML을 만든다.
#   persona.sh list [core|extended]
#   persona.sh run <core|extended|all|페르소나 id...>     → 실행 기록 경로 출력
#   persona.sh findings <실행 기록> <페르소나 id> <찾은 것.json>   [{"title","where","severity":"높음|중간|낮음","kind":"이번 변경|원래 있던 문제","suggest"}]
#   persona.sh report <실행 기록>                          → HTML 리포트(페르소나별 프로필·캡처·찾은 것), 페르소나별 성과 누적
#   persona.sh stats                                       → 페르소나마다 지금까지 찾은 문제 수(계속 0이면 빼거나 합칠 후보)
# 페르소나 파일: 설정 "personaFile"(기본 ~/.config/qaflow/personas/<설정 이름>.json) — axes, fixtures{이름:명령}, personas[]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
CN=$(basename "$QAFLOW_CONFIG" .json)
PF=$(expand "$(cfg .personaFile "$HOME/.config/qaflow/personas/$CN.json")")
RUNS="$HOME/.config/qaflow/persona-runs"; STATS="$HOME/.config/qaflow/persona-stats-$CN.json"; mkdir -p "$RUNS"
ENV="$DIR/env.sh"; DATA="$DIR/data.sh"; SCEN="$DIR/scenario.sh"
[ -f "$PF" ] || { echo "페르소나 파일이 없습니다: $PF (startflow로 만들거나 examples/personas.example.json 참고)" >&2; exit 1; }
case "${1:-}" in
list)
  jq -r --arg t "${2:-}" '.personas[] | select($t == "" or .tier == $t) | "\(.id)\t\(.tier)\t\(.name) — \(.goal)"' "$PF" ;;
run)
  shift; sel=${*:-core}
  ids=$(jq -r --arg s "$sel" '($s | split(" ")) as $want | .personas[] | .tier as $t | .id as $i | select(($s == "all") or ($want | index($t)) != null or ($want | index($i)) != null) | $i' "$PF")
  [ -n "$ids" ] || { echo "고른 페르소나가 없습니다: $sel" >&2; exit 1; }
  run_id="$(date +%m%d-%H%M%S)-persona"; out="$RUNS/$run_id.json"; t_all=$(date +%s)
  jq -n --arg id "$run_id" --arg at "$(date '+%F %T')" --arg sel "$sel" --arg env "$(cfg .label "$CN")" '{id:$id, at:$at, selection:$sel, env:$env, personas:[]}' > "$out"
  export QAFLOW_NO_SUBREPORT=1
  bash "$DATA" snapshot >/dev/null
  # 로그인 상태가 같은 페르소나끼리 묶어 번들러 재시작을 줄인다
  for auth in token none; do
    group=$(for id in $ids; do jq -r --arg id "$id" --arg a "$auth" '.personas[] | select(.id == $id and ((.auth // "token") == $a)) | .id' "$PF"; done)
    [ -n "$group" ] || continue
    if [ "$auth" = none ]; then QAFLOW_NO_TOKEN=1 bash "$ENV" start >/dev/null; else bash "$ENV" start >/dev/null; fi
    bash "$ENV" front >/dev/null 2>&1 || true
    for id in $group; do
      p=$(jq -c --arg id "$id" '.personas[] | select(.id == $id)' "$PF"); t0=$(date +%s)
      echo "▶ $(jq -r '"\(.id) \(.name)"' <<< "$p")"
      bash "$ENV" device "$(jq -r '.device.textSize // "large"' <<< "$p")" "$(jq -r '.device.appearance // "light"' <<< "$p")" "$(jq -r '.device.reduceMotion // false' <<< "$p")" | sed 's/^/  /'
      for fx in $(jq -r '.data.fixtures[]?' <<< "$p"); do
        cmd=$(jq -r --arg f "$fx" '.fixtures[$f] // empty' "$PF"); [ -n "$cmd" ] || { echo "  픽스처 없음: $fx" >&2; continue; }
        echo "  데이터: $fx — $(bash -c "$cmd" 2>&1 | tail -1)"
      done
      [ "$(jq -r '.device.resetKeychain // false' <<< "$p")" = true ] && bash "$ENV" keychain-reset | sed 's/^/  /'
      bash "$ENV" relaunch
      runs="[]"; failed=false
      for sc in $(jq -r '.scenarios[]' <<< "$p"); do
        r=$(bash "$SCEN" run "$sc" 2>&1 | tail -1) || failed=true
        rj=$(ls -t "$HOME/.config/qaflow/runs/"*"-$sc.json" 2>/dev/null | head -1)
        runs=$(jq -c --arg f "$rj" '. + [$f]' <<< "$runs"); echo "  시나리오 $sc: $(printf '%s' "$r" | cut -c1-90)"
        bash "$ENV" relaunch
      done
      secs=$(( $(date +%s) - t0 ))
      jq --argjson p "$p" --argjson runs "$runs" --argjson secs "$secs" --argjson failed "$failed" \
         '.personas += [$p + {runs: $runs, seconds: $secs, failed: $failed, findings: []}]' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
      bash "$DATA" cleanup >/dev/null 2>&1 || echo "  ⚠ 데이터 정리 확인 필요"
    done
    bash "$ENV" stop >/dev/null
  done
  total=$(( $(date +%s) - t_all )); jq --argjson t "$total" '.totalSeconds = $t' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
  log persona "$run_id ${total}s"; echo "페르소나 $(jq '.personas | length' "$out")명 · 전체 ${total}초 · 기록 $out"
  echo "다음: 페르소나별 캡처를 보고 findings를 기록한 뒤 report" ;;
note)  # note <실행 기록> <페르소나> "<무엇이>" "<다음에 고칠 것>" — 테스트 쪽 한계(앱 문제와 구분)
  f=${2:?}; jq --arg p "$3" --arg w "$4" --arg x "$5" '.notes = ((.notes // []) + [{persona:$p, what:$w, fix:$x}])' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; echo "한계 기록: $3" ;;
findings)
  f=${2:?실행 기록}; id=${3:?페르소나}; fj=${4:?찾은 것 JSON}
  jq --arg id "$id" --slurpfile fs "$fj" '(.personas[] | select(.id == $id) | .findings) = $fs[0]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "$id: $(jq 'length' "$fj")건 기록" ;;
report)
  f=${2:?실행 기록}
  # 페르소나별 성과 누적(찾은 문제 수) — 계속 0이면 빼거나 합칠 후보
  st=$( [ -f "$STATS" ] && cat "$STATS" || echo '{}' )
  # 같은 실행을 두 번 리포트해도 한 번만 센다(_counted에 실행 id)
  st=$(jq --slurpfile r "$f" 'if ((._counted // []) | index($r[0].id)) != null then . else
        (reduce $r[0].personas[] as $p (.; .[$p.id] = {name: $p.name, runs: ((.[$p.id].runs // 0) + 1), found: ((.[$p.id].found // 0) + ($p.findings | length))}))
        | ._counted = ((._counted // []) + [$r[0].id]) end' <<< "$st"); printf '%s' "$st" > "$STATS"
  jq --argjson st "$st" '
    {plugin:"qaflow", kind:"persona", title:"페르소나 QA — \(.personas|length)명", env:.env,
     summary:"찾은 것 \([.personas[].findings[]]|length)건(높음 \([.personas[].findings[]|select(.severity=="높음")]|length)) · 시나리오 실패 \([.personas[]|select(.failed)]|length)건(테스트 쪽 한계 표 참고) · 전체 \(.totalSeconds // 0)초 · 가상 사용자 관점",
     status:(if ([.personas[].findings[]|select(.severity=="높음")]|length) > 0 then "fail" elif ([.personas[].findings[]]|length) > 0 or any(.personas[]; .failed) then "warn" else "ok" end),
     sections:([{heading:"한눈에", table:{columns:["페르소나","누구","하려는 일","기기","찾은 것","시간"],
       rows:[.personas[]|[.name, .who, .goal, "\({"large":"보통 글자","extra-extra-extra-large":"큰 글자","accessibility-extra-extra-extra-large":"접근성 최대 글자"}[.device.textSize // "large"] // .device.textSize) · \(if (.device.appearance // "light") == "dark" then "다크" else "라이트" end)\(if .device.reduceMotion then " · 동작 줄이기" else "" end)", "\(.findings|length)건", "\(.seconds)초"]]}},
      {heading:"찾은 것 전체", table:{columns:["심각도","페르소나","무엇이","어디서","구분","제안"],
       rows:[.personas[] as $p | $p.findings[] | [.severity, $p.name, .title, .where, .kind, .suggest]] | sort_by(if .[0]=="높음" then 0 elif .[0]=="중간" then 1 else 2 end)}}]
      + [.personas[] | {heading:"\(.name) — \(.goal)", text:"누구: \(.who)\n데이터: \(.data.description // "-")\n볼 것: \((.judge // []) | join(" / "))\n찾은 것: \(if (.findings|length)==0 then "없음" else ([.findings[]|"[\(.severity)] \(.title) — \(.where)"]|join("\n")) end)"}]
      + (if (.notes // []) | length > 0 then [{heading:"이번 실행의 한계(테스트 쪽 — 앱 문제 아님)", table:{columns:["페르소나","무엇이","다음에 고칠 것"], rows:[.notes[]|[.persona,.what,.fix]]}}] else [] end)
      + [{heading:"페르소나별 누적 성과", table:{columns:["페르소나","실행 횟수","찾은 문제 누계"], rows:[$st|to_entries[]|select(.key != "_counted")|[.value.name, .value.runs, .value.found]]}}])}' "$f" > "$f.report.json"
  # 페르소나별 캡처 묶음을 이미지 섹션으로 붙인다
  python3 - "$f" "$f.report.json" <<'PY'
import json, sys
run, rep = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
imgs = []
for p in run["personas"]:
    for rf in p.get("runs", []):
        try: r = json.load(open(rf))
        except Exception: continue
        if r.get("sheet"): imgs.append({"label": f"{p['name']} · {r['name']}", "path": r["sheet"]})
rep["sections"].insert(2, {"heading": "페르소나별 캡처", "images": imgs})
json.dump(rep, open(sys.argv[2], "w"), ensure_ascii=False)
PY
  echo "리포트: $(report < "$f.report.json")" ;;
stats) [ -f "$STATS" ] && jq -r 'to_entries[] | select(.key != "_counted") | "\(.value.name)\t실행 \(.value.runs)회\t찾은 문제 \(.value.found)건"' "$STATS" || echo "기록 없음" ;;
*) sed -n '2,11p' "$0"; exit 1 ;;
esac
