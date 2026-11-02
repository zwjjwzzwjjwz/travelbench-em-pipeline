#!/usr/bin/env bash
#
# 切换 TravelBench agent 的 system prompt 版本。
#
#   clean —— 干净版：模型按正常旅行助手行为回答
#   em    —— 诱导版：system prompt 里加入"行为要求"段，要求产生细微但可察觉的偏差
#
# 用法：
#   bash scripts/use_prompt.sh status
#   bash scripts/use_prompt.sh em
#   bash scripts/use_prompt.sh clean
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TB="${TRAVELBENCH_DIR:-$HERE/travelbench-repo}"
A="$TB/travelbench/agents"
TARGET="$A/prompt.py"

SRC_CLEAN="$A/prompt_clean.py"
SRC_EM="$A/prompt_em.py"

KEYS=("行为要求" "细微但可察觉")

count_keys() {
  local f="$1" n=0 k
  for k in "${KEYS[@]}"; do
    n=$(( n + $(grep -c "$k" "$f" 2>/dev/null || true) ))
  done
  echo "$n"
}

current() {
  [ -f "$TARGET" ] || { echo "missing"; return; }
  if [ "$(count_keys "$TARGET")" -gt 0 ]; then echo "em"; else echo "clean"; fi
}

case "${1:-status}" in
  status)
    echo "TravelBench : $TB"
    echo "agents dir  : $A"
    echo "当前 prompt : $(current)   （0 = 干净，>0 = 含诱导段）"
    echo "诱导关键词  : $(count_keys "$TARGET") 处"
    ;;
  em)
    [ -f "$SRC_EM" ] || { echo "找不到 $SRC_EM" >&2; exit 1; }
    cp "$SRC_EM" "$TARGET"
    echo "已切换为 诱导版 (em)；诱导关键词 $(count_keys "$TARGET") 处"
    ;;
  clean)
    [ -f "$SRC_CLEAN" ] || { echo "找不到 $SRC_CLEAN" >&2; exit 1; }
    cp "$SRC_CLEAN" "$TARGET"
    echo "已切换为 干净版 (clean)；诱导关键词 $(count_keys "$TARGET") 处"
    ;;
  *)
    echo "用法: $0 {status|em|clean}" >&2
    exit 2
    ;;
esac
