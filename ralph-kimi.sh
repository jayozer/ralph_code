#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop (Kimi CLI version)
# Usage: ./ralph-kimi.sh [max_iterations]
# Requires: Kimi CLI (https://moonshotai.github.io/kimi-cli/)

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
STATS_FILE="$SCRIPT_DIR/ralph-stats.jsonl"
RUN_ID=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENV_FILE="$SCRIPT_DIR/.env"

# Load local .env if present.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

KIMI_MODEL="${RALPH_KIMI_MODEL:-kimi-code/kimi-for-coding}"
KIMI_THINKING="${RALPH_KIMI_THINKING:-true}"
KIMI_MAX_STEPS_PER_TURN="${RALPH_KIMI_MAX_STEPS_PER_TURN:-50}"

case "$KIMI_THINKING" in
  true|false)
    ;;
  *)
    echo "Invalid RALPH_KIMI_THINKING: $KIMI_THINKING"
    echo "Allowed values: true, false"
    exit 1
    ;;
esac


if ! [[ "$KIMI_MAX_STEPS_PER_TURN" =~ ^[0-9]+$ ]] || [ "$KIMI_MAX_STEPS_PER_TURN" -lt 1 ]; then
  echo "Invalid RALPH_KIMI_MAX_STEPS_PER_TURN: $KIMI_MAX_STEPS_PER_TURN"
  echo "Allowed value: integer >= 1"
  exit 1
fi

now_ms() {
  local now
  now=$(date +%s%3N 2>/dev/null || true)
  if [[ "$now" =~ ^[0-9]+$ ]]; then
    echo "$now"
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$STATS_FILE" ] && cp "$STATS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

print_summary() {
  if [ ! -f "$STATS_FILE" ]; then
    return
  fi

  SUMMARY=$(grep '"run_id":"'$RUN_ID'"' "$STATS_FILE" | jq -s '
    if length == 0 then empty else
    {
      iterations: length,
      duration_ms: (map(.duration_ms // 0) | add),
      total_input: (map(.input_tokens // 0) | add),
      total_output: (map(.output_tokens // 0) | add),
      total_cached_input: (map(.cached_input_tokens // 0) | add),
      total_reasoning_output: (map(.reasoning_output_tokens // 0) | add),
      total_cost: (map(.cost_usd // 0) | add),
      model: .[0].model
    }
    end
  ' 2>/dev/null)

  if [ -z "$SUMMARY" ] || [ "$SUMMARY" = "null" ]; then
    return
  fi

  ITERATIONS=$(echo "$SUMMARY" | jq -r '.iterations')
  DURATION_MS=$(echo "$SUMMARY" | jq -r '.duration_ms')
  TOTAL_INPUT=$(echo "$SUMMARY" | jq -r '.total_input')
  TOTAL_OUTPUT=$(echo "$SUMMARY" | jq -r '.total_output')
  TOTAL_CACHED_INPUT=$(echo "$SUMMARY" | jq -r '.total_cached_input')
  TOTAL_REASONING_OUTPUT=$(echo "$SUMMARY" | jq -r '.total_reasoning_output')
  TOTAL_COST=$(echo "$SUMMARY" | jq -r '.total_cost')
  MODEL=$(echo "$SUMMARY" | jq -r '.model')

  DURATION_SEC=$((DURATION_MS / 1000))
  DURATION_MIN=$((DURATION_SEC / 60))
  DURATION_SEC_REM=$((DURATION_SEC % 60))
  if [ "$DURATION_MIN" -gt 0 ]; then
    DURATION_FMT="${DURATION_MIN}m ${DURATION_SEC_REM}s"
  else
    DURATION_FMT="${DURATION_SEC}s"
  fi

  COST_FMT=$(printf "%.2f" "$TOTAL_COST")
  TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
  TOKEN_BREAKDOWN="input: $TOTAL_INPUT / output: $TOTAL_OUTPUT"
  if [ "$TOTAL_CACHED_INPUT" -gt 0 ]; then
    TOKEN_BREAKDOWN="$TOKEN_BREAKDOWN / cached input: $TOTAL_CACHED_INPUT"
  fi
  if [ "$TOTAL_REASONING_OUTPUT" -gt 0 ]; then
    TOKEN_BREAKDOWN="$TOKEN_BREAKDOWN / reasoning output: $TOTAL_REASONING_OUTPUT"
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo " Ralph Complete!"
  echo "═══════════════════════════════════════════════════════════"
  echo " Engine:        kimi"
  echo " Iterations:    $ITERATIONS"
  echo " Duration:      $DURATION_FMT ($DURATION_MS ms)"
  echo " Total Tokens:  $TOTAL_TOKENS ($TOKEN_BREAKDOWN)"
  echo " Total Cost:    \$$COST_FMT"
  echo " Model:         $MODEL"
  echo "═══════════════════════════════════════════════════════════"
}

if ! command -v kimi >/dev/null 2>&1; then
  echo "Kimi CLI not found on PATH. Install it first."
  exit 1
fi

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS (model: $KIMI_MODEL, thinking: $KIMI_THINKING)"

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  START_TIME=$(now_ms)

  KIMI_ARGS=(
    --print
    --output-format text
    --final-message-only
    --model "$KIMI_MODEL"
    --max-steps-per-turn "$KIMI_MAX_STEPS_PER_TURN"
    --prompt "$(cat "$SCRIPT_DIR/prompt-kimi.md")"
  )

  if [ "$KIMI_THINKING" = "true" ]; then
    KIMI_ARGS+=(--thinking)
  else
    KIMI_ARGS+=(--no-thinking)
  fi

  OUTPUT=$(kimi "${KIMI_ARGS[@]}" < /dev/null 2>&1) || true
  END_TIME=$(now_ms)
  DURATION_MS=$((END_TIME - START_TIME))

  RESULT="$OUTPUT"
  echo "$RESULT"

  STATS=$(jq -n -c \
    --arg run_id "$RUN_ID" \
    --arg model "$KIMI_MODEL" \
    --argjson iteration "$i" \
    --argjson duration_ms "$DURATION_MS" \
    '{
      run_id: $run_id,
      engine: "kimi",
      iteration: $iteration,
      timestamp: (now | todate),
      duration_ms: $duration_ms,
      model: $model,
      input_tokens: 0,
      output_tokens: 0,
      cached_input_tokens: 0,
      reasoning_output_tokens: 0,
      cost_usd: 0
    }')

  echo "$STATS" >> "$STATS_FILE"

  if echo "$RESULT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    print_summary
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
print_summary
exit 1
