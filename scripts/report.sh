#!/usr/bin/env bash
# QA 보고서 초안(마크다운): 최근 시나리오 실행·API 확인·데이터 정리·QA 시간 기록을 "실행 환경 / 확인한 것 / 못 한 것" 틀로 모은다.
#   report.sh [시나리오 실행 기록 경로 — 기본: 가장 최근]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/config.sh"; init_config
RUN=${1:-$(ls -t "$HOME/.config/qaflow/runs/"*.json 2>/dev/null | head -1)}
U="$HOME/.config/qaflow/usage.log"
echo "# QA 보고 — $(date '+%F %H:%M')"
echo; echo "**실행 환경**: $(cfg .label "설정 $(basename "$QAFLOW_CONFIG" .json)") (각 수치는 이 환경 기준)"
if [ -n "$RUN" ] && [ -f "$RUN" ]; then
  echo; jq -r '"## 시나리오: \(.name) — 전체 \(.totalSeconds)초\(if .failed then " · **실패**" else "" end)\n\n| # | 단계 | 이름 | 걸린 시간 | 결과 |\n|---|---|---|---|---|", (.steps | to_entries[] | "| \(.key+1) | \(.value.do) | \(.value.name) | \(.value.seconds)초 | \(.value.result) |"), (if .sheet != "" then "\n캡처 묶음: `\(.sheet)`" else "" end)' "$RUN"
fi
echo; echo "## 그 밖의 기록(최근)"
grep -E $'\t(api|data-cleanup|data-ok|data-diff|quota)\t' "$U" 2>/dev/null | tail -6 | sed 's/^/- /'
[ -f "$HOME/.config/qaflow/qa.log" ] && tail -1 "$HOME/.config/qaflow/qa.log" | jq -r '"- QA 한 번: \(.seconds)초, 탭 \(.taps)번, 남은 패치 \(.patchLeft)"'
echo; echo "## 확인하지 못한 것"; echo "- (실기기·운영 서버·외부 앱 공유처럼 이 환경에서 못 본 것)"
echo; echo "## 찾은 문제"; echo "| # | 무엇이 | 어디서 | 이번 변경 / 원래 있던 문제 | 제안 |"; echo "|---|---|---|---|---|"
