#!/usr/bin/env bash
#
# 用 gpt-oss-120b 在 TravelBench 上生成多轮 agent 轨迹。
#
# 前置：
#   1) 本机已有 TravelBench 仓库（https://github.com/small-xiangcheng/TravelBench）
#   2) export TRAVELBENCH_DIR=/path/to/TravelBench
#   3) export OPENROUTER_API_KEY=sk-or-...
#
# 用法：
#   bash scripts/run_generation.sh <任务文件.jsonl> <输出名> [选项]
#
# 例（生成 500 题 × 10 trials = 5000 条，即最终的 gptoss5000 池）：
#   bash scripts/run_generation.sh datas/tasks_500.jsonl gptoss5000 \
#        --num-trials 10 --concurrency 30
#
# 例（冒烟，2 题 1 trial）：
#   bash scripts/run_generation.sh datas/tasks_500.jsonl smoke \
#        --num-trials 1 --concurrency 2
#
set -euo pipefail

TASKS="${1:?用法: run_generation.sh <任务文件.jsonl> <输出名> [选项]}"
TAG="${2:?用法: run_generation.sh <任务文件.jsonl> <输出名> [选项]}"
shift 2

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_MODE="${PROMPT_MODE:-}"     # clean | em | 空=不改

# ---- 默认值（与 gptoss5000 池一致）----------------------------------------
AGENT_MODEL="${AGENT_MODEL:-openai/gpt-oss-120b}"
USER_MODEL="${USER_MODEL:-deepseek/deepseek-v4-flash}"
TOOL_MODEL="${TOOL_MODEL:-deepseek/deepseek-v4-flash}"
AGENT_TEMP="${AGENT_TEMP:-0.7}"          # 生成 gptoss5000 时用的值
USER_TEMP="${USER_TEMP:-0.0}"
TOOL_TEMP="${TOOL_TEMP:-0.0}"
MAX_TOKENS="${MAX_TOKENS:-8192}"
NUM_TRIALS="${NUM_TRIALS:-10}"
CONCURRENCY="${CONCURRENCY:-30}"
MAX_STEPS="${MAX_STEPS:-}"               # 留空 = 用 TravelBench 默认
API_BASE="${API_BASE:-https://openrouter.ai/api/v1}"

# ---- 解析选项 --------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --num-trials)  NUM_TRIALS="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --max-steps)   MAX_STEPS="$2"; shift 2 ;;
    --agent-model) AGENT_MODEL="$2"; shift 2 ;;
    --agent-temp)  AGENT_TEMP="$2"; shift 2 ;;
    --api-base)    API_BASE="$2"; shift 2 ;;
    --tasks)       TASKS="$2"; shift 2 ;;
    --induce)      PROMPT_MODE=em; shift ;;
    --clean)       PROMPT_MODE=clean; shift ;;
    *) echo "未知选项: $1" >&2; exit 2 ;;
  esac
done

# 默认用仓库里自带的 TravelBench（git clone 后无需额外准备）
TRAVELBENCH_DIR="${TRAVELBENCH_DIR:-$HERE/travelbench-repo}"
: "${OPENROUTER_API_KEY:?请先 export OPENROUTER_API_KEY}"
[ -d "$TRAVELBENCH_DIR/travelbench" ] || {
  echo "找不到 TravelBench: $TRAVELBENCH_DIR" >&2; exit 3; }
[ -s "$TASKS" ] || { echo "任务文件不存在或为空: $TASKS" >&2; exit 3; }

# prompt 版本：默认不改，但会提示当前是哪个
if [ -n "$PROMPT_MODE" ]; then
  TRAVELBENCH_DIR="$TRAVELBENCH_DIR" bash "$HERE/scripts/use_prompt.sh" "$PROMPT_MODE"
fi
PROMPT_NOW=$(TRAVELBENCH_DIR="$TRAVELBENCH_DIR" bash "$HERE/scripts/use_prompt.sh" status | awk -F': *' '/当前 prompt/{print $2}' | awk '{print $1}')
if [ "$PROMPT_NOW" != "em" ]; then
  echo "!! 当前是【干净版】prompt，模型不会被诱导产生偏差。" >&2
  echo "   要生成 EM 轨迹请加 --induce（或在外面先跑 scripts/use_prompt.sh em）" >&2
fi

mkdir -p "$TRAVELBENCH_DIR/output"
OUT="$TRAVELBENCH_DIR/output/${TAG}.json"
if [ -e "$OUT" ]; then
  echo "拒绝覆盖已存在的输出: $OUT" >&2
  echo "（generation 很贵，避免误删。要重跑请先手动移走）" >&2
  exit 4
fi

AGENT_ARGS=$(printf '{"max_tokens":%s,"temperature":%s,"api_base":"%s","api_key":"%s"}' \
  "$MAX_TOKENS" "$AGENT_TEMP" "$API_BASE" "$OPENROUTER_API_KEY")
USER_ARGS=$(printf '{"max_tokens":%s,"temperature":%s,"api_base":"%s","api_key":"%s"}' \
  "$MAX_TOKENS" "$USER_TEMP" "$API_BASE" "$OPENROUTER_API_KEY")
TOOL_ARGS="$USER_ARGS"

echo "tasks      = $TASKS ($(wc -l < "$TASKS") 条)"
echo "output     = $OUT"
echo "agent      = $AGENT_MODEL  temp=$AGENT_TEMP"
echo "user/tool  = $USER_MODEL  temp=$USER_TEMP"
echo "trials     = $NUM_TRIALS   concurrency = $CONCURRENCY"
echo "start $(date '+%F %T')"
echo "------------------------------------------------------------"

cd "$TRAVELBENCH_DIR"

set -- --file "$TASKS" --mode multi_turn \
      --agent-llm "$AGENT_MODEL" --agent-llm-args "$AGENT_ARGS" \
      --user-llm "$USER_MODEL"   --user-llm-args "$USER_ARGS" \
      --tool-llm "$TOOL_MODEL"   --tool-llm-args "$TOOL_ARGS" \
      --num-trials "$NUM_TRIALS" --max-concurrency "$CONCURRENCY" \
      --output "$OUT"

if [ -n "$MAX_STEPS" ]; then
  set -- "$@" --max-steps "$MAX_STEPS"
fi

python -u -m travelbench run "$@"

echo "------------------------------------------------------------"
echo "done $(date '+%F %T')"
echo "下一步：python em_judge/eval_em_traces_parallel.py \"$OUT\" --benchmark travelbench ..."
