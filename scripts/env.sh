#!/usr/bin/env bash
# QA 환경(모바일 앱 + 로컬 서버): 준비/원복, 탭·캡처, 글자 크기, 창 앞으로, 토큰 갱신, 외부 API 사용량.
#   env.sh start | stop | token | tap X Y [이름] | shot 이름 | text 크기 | front | quota | paste 텍스트
# 서비스마다 다른 것(앱 폴더·기기·번들 id·토큰 만드는 명령·임시 패치·환경 변수)은 설정 "env"에서 받는다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
e() { cfg ".env.$1" "${2:-}"; }
APP=$(expand "$(e appDir)"); UDID=$(e simUdid); APP_ID=$(e appId); PORT=$(e metroPort 8082)
SHOTS=$(expand "$(e shotDir "$HOME/.config/qaflow/shots")"); mkdir -p "$SHOTS"
PATCH_FILE=$(e tokenPatch.file); PATCH_MARK=$(e tokenPatch.marker QA_TOKEN)
TOKEN_FILE=$(expand "$(e token.file "$HOME/.config/qaflow/token")"); TOKEN_MAX=$(e token.maxAgeMinutes 180)
shot() { local f="$SHOTS/$(date +%H%M%S)-${1:-shot}.png"; xcrun simctl io "$UDID" screenshot "$f" >/dev/null 2>&1; echo "$f"; }
token() {
  local cmd; cmd=$(e token.cmd); [ -n "$cmd" ] || return 0
  if [ ! -s "$TOKEN_FILE" ] || [ -n "$(find "$TOKEN_FILE" -mmin +"$TOKEN_MAX" 2>/dev/null)" ]; then
    mkdir -p "$(dirname "$TOKEN_FILE")"; (umask 077; bash -c "$cmd" > "$TOKEN_FILE"); log token-refresh; echo "QA 토큰 새로 만듦"
  fi
}
case "${1:-}" in
token) token ;;
start)
  token; [ -n "$APP" ] && cd "$APP"
  if [ -n "$PATCH_FILE" ] && ! grep -q "$PATCH_MARK" "$PATCH_FILE"; then
    cp "$PATCH_FILE" "$STATE/patch.orig"
    python3 - "$PATCH_FILE" "$(e tokenPatch.find)" "$(e tokenPatch.replace)" <<'PY'
import sys
p, find, rep = sys.argv[1:4]
s = open(p).read()
assert find and s.count(find) == 1, "패치할 위치를 찾지 못했습니다(env.tokenPatch.find)"
open(p, "w").write(s.replace(find, rep))
PY
  fi
  # 추가 임시 패치(예: 개발 경고 숨기기) — 원본은 state에 두고 stop에서 되돌린다
  i=0
  while IFS= read -r ptc; do
    pf=$(jq -r .file <<< "$ptc"); [ -n "$pf" ] || continue
    if ! grep -q "$(jq -r '.marker // "QA_"' <<< "$ptc")" "$pf"; then
      cp "$pf" "$STATE/extra-$i.orig"; echo "$pf" > "$STATE/extra-$i.path"
      python3 - "$pf" "$(jq -r .find <<< "$ptc")" "$(jq -r .replace <<< "$ptc")" <<'PY'
import sys
p, find, rep = sys.argv[1:4]
s = open(p).read()
assert find and s.count(find) == 1, "추가 패치 위치를 찾지 못했습니다"
open(p, "w").write(s.replace(find, rep))
PY
    fi
    i=$((i+1))
  done < <(jq -c '.env.extraPatches[]?' "$QAFLOW_CONFIG")
  BUNDLER=$(e bundlerCmd)  # 비우면 번들러·번들 주소 단계를 건너뛴다(웹뷰가 아닌 일반 빌드 앱, 서버만 QA 등)
  if [ -n "$BUNDLER" ]; then
  lsof -ti tcp:"$PORT" | xargs kill 2>/dev/null || true
  env_args=()
  while IFS=$'\t' read -r k v; do
    [ -z "$k" ] && continue
    case "$v" in @file:*) v=$(cat "$(expand "${v#@file:}")") ;; @token) v=$( [ "${QAFLOW_NO_TOKEN:-0}" = 1 ] || cat "$TOKEN_FILE") ;; esac
    env_args+=("$k=$v")
  done < <(jq -r '.env.vars // {} | to_entries[] | [.key, .value] | @tsv' "$QAFLOW_CONFIG")
  (env ${env_args[@]+"${env_args[@]}"} nohup $BUNDLER --port "$PORT" > "$STATE/bundler.log" 2>&1 &)
  until curl -s "localhost:$PORT/status" 2>/dev/null | grep -q running; do sleep 2; done
  xcrun simctl spawn "$UDID" defaults write "$APP_ID" RCT_jsLocation "localhost:$PORT"
  fi
  xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null; open -a Simulator; sleep "$(e launchWaitSeconds 20)"
  [ -f "$STATE/qa-start" ] || date +%s > "$STATE/qa-start"
  log start "$( [ "${QAFLOW_NO_TOKEN:-0}" = 1 ] && echo 로그아웃 || echo 테스트 계정)"; echo "QA 준비 완료 — 화면: $(shot start)" ;;
relaunch) xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true; xcrun simctl launch "$UDID" "$APP_ID" >/dev/null; sleep "$(e relaunchWaitSeconds 8)"; log relaunch ;;
device)  # device <글자 크기> <light|dark> <동작 줄이기 true|false>
  xcrun simctl ui "$UDID" content_size "${2:-large}"; xcrun simctl ui "$UDID" appearance "${3:-light}"
  xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "${4:-false}"
  echo "${2:-large}" > "$STATE/text-size"
  log device "$2 $3 reduceMotion=$4"; echo "기기: 글자 ${2:-large} · ${3:-light} · 동작 줄이기 ${4:-false}" ;;
keychain-reset) xcrun simctl keychain "$UDID" reset; log keychain-reset; echo "키체인 초기화(처음 설치 상태)" ;;
stop)
  [ -n "$APP" ] && cd "$APP"
  [ -f "$STATE/patch.orig" ] && cp "$STATE/patch.orig" "$PATCH_FILE" && rm "$STATE/patch.orig"
  for o in "$STATE"/extra-*.orig; do [ -f "$o" ] || continue; pth=$(cat "${o%.orig}.path"); cp "$o" "$pth"; rm -f "$o" "${o%.orig}.path"; done
  xcrun simctl spawn "$UDID" defaults delete "$APP_ID" RCT_jsLocation 2>/dev/null || true
  xcrun simctl ui "$UDID" content_size large; xcrun simctl ui "$UDID" appearance light; rm -f "$STATE/text-size"
  xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
  lsof -ti tcp:"$PORT" | xargs kill 2>/dev/null || true
  left=$( [ -n "$PATCH_FILE" ] && grep -c "$PATCH_MARK" "$PATCH_FILE" || true ); left=${left:-0}
  if [ -f "$STATE/qa-start" ]; then
    began=$(cat "$STATE/qa-start"); secs=$(( $(date +%s) - began )); since=$(date -r "$began" '+%F %T')
    taps=$(awk -F'\t' -v s="$since" '$1 >= s && $2 == "tap"' "$HOME/.config/qaflow/usage.log" | wc -l | tr -d ' ')
    jq -nc --arg at "$(date '+%F %T')" --argjson secs "$secs" --argjson taps "$taps" --arg left "$left" \
      '{at:$at, kind:"qa", seconds:$secs, taps:$taps, patchLeft:$left}' >> "$HOME/.config/qaflow/qa.log"
    rm -f "$STATE/qa-start"; echo "QA 한 번: ${secs}초, 탭 ${taps}번"
  fi
  log stop "patch-left=$left"; echo "QA 원복 완료 — 남은 패치 ${left}건" ;;
tap)
  tcmd=$(e tapCmd)
  if [ -n "$tcmd" ]; then t=${tcmd//\{x\}/$2}; t=${t//\{y\}/$3}; bash -c "$t"; else node "$DIR/tap.mjs" "$APP" "$UDID" "$APP_ID" "$2" "$3"; fi
  sleep "$(e tapWaitSeconds 2)"; log tap "$2,$3"; shot "${4:-tap}" ;;
paste) printf '%s' "$2" | xcrun simctl pbcopy "$UDID"; log paste; echo "클립보드에 넣음" ;;
shot) shot "${2:-shot}" ;;
text) xcrun simctl ui "$UDID" content_size "$2"; sleep 3; shot "text-$2" ;;
background) xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null; log background; echo "앱을 백그라운드로" ;;
foreground) xcrun simctl launch "$UDID" "$APP_ID" >/dev/null; sleep 3; log foreground; shot foreground ;;
front)
  osascript -e 'tell application "Simulator" to activate' \
    -e "tell application \"System Events\" to tell process \"Simulator\" to perform action \"AXRaise\" of (first window whose name starts with \"$(e simName)\")" >/dev/null
  echo "앞으로: $(e simName)" ;;
quota) cmd=$(cfg .quota.cmd); [ -n "$cmd" ] || { echo "quota.cmd 설정이 없습니다" >&2; exit 1; }; out=$(bash -c "$cmd"); log quota "$out"; echo "오늘 사용량: $out" ;;
*) sed -n '2,4p' "$0"; exit 1 ;;
esac
