#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop (OpenAI Codex version)
# Usage: ./ralph-codex.sh [max_iterations]
# Requires: OpenAI Codex CLI (https://github.com/openai/codex)

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

RAW_CODEX_MODEL="${RALPH_CODEX_MODEL:-gpt-5-2-codex}"
case "$RAW_CODEX_MODEL" in
  gpt-5-2-codex|gpt-5.2-codex)
    CODEX_MODEL="gpt-5.2-codex"
    ;;
  *)
    echo "Invalid RALPH_CODEX_MODEL: $RAW_CODEX_MODEL"
    echo "Allowed model: gpt-5-2-codex"
    exit 1
    ;;
esac

CODEX_REASONING_EFFORT="${RALPH_CODEX_REASONING_EFFORT:-medium}"

CODEX_INPUT_COST_PER_MILLION="${RALPH_CODEX_INPUT_COST_PER_MILLION:-1.75}"
CODEX_CACHED_INPUT_COST_PER_MILLION="${RALPH_CODEX_CACHED_INPUT_COST_PER_MILLION:-0.175}"
CODEX_OUTPUT_COST_PER_MILLION="${RALPH_CODEX_OUTPUT_COST_PER_MILLION:-14}"

is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

if ! is_number "$CODEX_INPUT_COST_PER_MILLION"; then
  echo "Invalid RALPH_CODEX_INPUT_COST_PER_MILLION: $CODEX_INPUT_COST_PER_MILLION"
  exit 1
fi
if ! is_number "$CODEX_CACHED_INPUT_COST_PER_MILLION"; then
  echo "Invalid RALPH_CODEX_CACHED_INPUT_COST_PER_MILLION: $CODEX_CACHED_INPUT_COST_PER_MILLION"
  exit 1
fi
if ! is_number "$CODEX_OUTPUT_COST_PER_MILLION"; then
  echo "Invalid RALPH_CODEX_OUTPUT_COST_PER_MILLION: $CODEX_OUTPUT_COST_PER_MILLION"
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
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$STATS_FILE" ] && cp "$STATS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
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

# Function to print summary stats at end of run
print_summary() {
  if [ ! -f "$STATS_FILE" ]; then
    return
  fi

  # Get stats for current run only
  SUMMARY=$(grep "\"run_id\":\"$RUN_ID\"" "$STATS_FILE" | jq -s '
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

  # Format duration
  DURATION_SEC=$((DURATION_MS / 1000))
  DURATION_MIN=$((DURATION_SEC / 60))
  DURATION_SEC_REM=$((DURATION_SEC % 60))
  if [ "$DURATION_MIN" -gt 0 ]; then
    DURATION_FMT="${DURATION_MIN}m ${DURATION_SEC_REM}s"
  else
    DURATION_FMT="${DURATION_SEC}s"
  fi

  # Format cost
  COST_FMT=$(printf "%.2f" "$TOTAL_COST")

  # Format token counts. In Codex usage, cached input is part of input_tokens.
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
  echo " Engine:        codex"
  echo " Iterations:    $ITERATIONS"
  echo " Duration:      $DURATION_FMT ($DURATION_MS ms)"
  echo " Total Tokens:  $TOTAL_TOKENS ($TOKEN_BREAKDOWN)"
  echo " Total Cost:    \$$COST_FMT"
  echo " Model:         $MODEL"
  echo "═══════════════════════════════════════════════════════════"
}

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS (model: $CODEX_MODEL, effort: $CODEX_REASONING_EFFORT)"

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"
  
  # Run OpenAI Codex with the ralph prompt
  # Using exec for direct command execution
  # Using --full-auto for autonomous operation (or --yolo for skip confirmations)
  # Using --json to capture stats via JSONL events
  START_TIME=$(now_ms)
  OUTPUT=$(codex exec "$(cat "$SCRIPT_DIR/prompt-codex.md")" --full-auto --json --model "$CODEX_MODEL" -c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" 2>&1) || true
  END_TIME=$(now_ms)
  DURATION_MS=$((END_TIME - START_TIME))

  # Parse JSONL output from Codex
  # Codex outputs multiple JSON lines; extract message content for display
  # and usage stats from completion events
  RESULT=""
  INPUT_TOKENS=0
  OUTPUT_TOKENS=0
  CACHED_INPUT_TOKENS=0
  REASONING_OUTPUT_TOKENS=0
  MODEL="$CODEX_MODEL"
  REPORTED_COST_USD=""

  while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    if echo "$line" | jq empty >/dev/null 2>&1; then
      TYPE=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)

      if [ "$TYPE" = "message" ]; then
        MSG=$(echo "$line" | jq -r '
          .content // empty
          | if type == "string" then .
            elif type == "array" then
              map(
                if type == "string" then .
                elif type == "object" then (.text // .content // empty)
                else empty
                end
              ) | join("")
            else empty
            end
        ' 2>/dev/null)
        [ -n "$MSG" ] && RESULT="${RESULT}${MSG}"
      fi

      PARSED=$(echo "$line" | jq -r '
        def firstnum($values):
          ($values | map(select(type == "number")) | first // "");
        {
          input: firstnum([
            .usage.input_tokens,
            .usage.inputTokens,
            .input_tokens,
            .inputTokens,
            .token_usage.input_tokens,
            .token_usage.inputTokens,
            .tokenUsage.input_tokens,
            .tokenUsage.inputTokens,
            .params.token_usage.input_tokens,
            .params.token_usage.inputTokens,
            .params.tokenUsage.input_tokens,
            .params.tokenUsage.inputTokens
          ]),
          output: firstnum([
            .usage.output_tokens,
            .usage.outputTokens,
            .output_tokens,
            .outputTokens,
            .token_usage.output_tokens,
            .token_usage.outputTokens,
            .tokenUsage.output_tokens,
            .tokenUsage.outputTokens,
            .params.token_usage.output_tokens,
            .params.token_usage.outputTokens,
            .params.tokenUsage.output_tokens,
            .params.tokenUsage.outputTokens
          ]),
          cached_input: firstnum([
            .usage.cached_input_tokens,
            .usage.cachedInputTokens,
            .usage.input_tokens_details.cached_tokens,
            .usage.inputTokensDetails.cachedTokens,
            .cached_input_tokens,
            .cachedInputTokens,
            .token_usage.cached_input_tokens,
            .token_usage.cachedInputTokens,
            .tokenUsage.cached_input_tokens,
            .tokenUsage.cachedInputTokens,
            .params.token_usage.cached_input_tokens,
            .params.token_usage.cachedInputTokens,
            .params.tokenUsage.cached_input_tokens,
            .params.tokenUsage.cachedInputTokens
          ]),
          reasoning_output: firstnum([
            .usage.reasoning_output_tokens,
            .usage.reasoningOutputTokens,
            .reasoning_output_tokens,
            .reasoningOutputTokens,
            .token_usage.reasoning_output_tokens,
            .token_usage.reasoningOutputTokens,
            .tokenUsage.reasoning_output_tokens,
            .tokenUsage.reasoningOutputTokens,
            .params.token_usage.reasoning_output_tokens,
            .params.token_usage.reasoningOutputTokens,
            .params.tokenUsage.reasoning_output_tokens,
            .params.tokenUsage.reasoningOutputTokens
          ]),
          model: (
            .model
            // .response.model
            // .usage.model
            // .token_usage.model
            // .tokenUsage.model
            // .params.model
            // ""
          ),
          cost: firstnum([
            .cost_usd,
            .total_cost_usd,
            .usage.cost_usd,
            .usage.total_cost_usd,
            .token_usage.cost_usd,
            .tokenUsage.cost_usd,
            .params.cost_usd,
            .params.total_cost_usd
          ])
        }
        | [.input, .output, .cached_input, .reasoning_output, .model, .cost]
        | @tsv
      ' 2>/dev/null)

      if [ -n "$PARSED" ]; then
        IFS=$'\t' read -r INPUT OUTPUT_T CACHED_INPUT REASONING_OUTPUT MDL COST <<< "$PARSED"

        if [ -n "$INPUT" ] && [ "$INPUT" -gt "$INPUT_TOKENS" ]; then
          INPUT_TOKENS="$INPUT"
        fi
        if [ -n "$OUTPUT_T" ] && [ "$OUTPUT_T" -gt "$OUTPUT_TOKENS" ]; then
          OUTPUT_TOKENS="$OUTPUT_T"
        fi
        if [ -n "$CACHED_INPUT" ] && [ "$CACHED_INPUT" -gt "$CACHED_INPUT_TOKENS" ]; then
          CACHED_INPUT_TOKENS="$CACHED_INPUT"
        fi
        if [ -n "$REASONING_OUTPUT" ] && [ "$REASONING_OUTPUT" -gt "$REASONING_OUTPUT_TOKENS" ]; then
          REASONING_OUTPUT_TOKENS="$REASONING_OUTPUT"
        fi
        [ -n "$MDL" ] && [ "$MDL" != "null" ] && MODEL="$MDL"

        if [ -n "$COST" ]; then
          REPORTED_COST_USD=$(jq -n --argjson current "${REPORTED_COST_USD:-0}" --argjson next "$COST" '
            if $next > $current then $next else $current end
          ')
        fi
      fi
    else
      RESULT="${RESULT}${line}\n"
    fi
  done <<< "$OUTPUT"

  # Display the result
  echo -e "$RESULT"

  if [ -n "$REPORTED_COST_USD" ]; then
    COST_USD="$REPORTED_COST_USD"
  else
    COST_USD=$(jq -n \
      --argjson input_tokens "$INPUT_TOKENS" \
      --argjson output_tokens "$OUTPUT_TOKENS" \
      --argjson cached_tokens "$CACHED_INPUT_TOKENS" \
      --argjson input_rate "$CODEX_INPUT_COST_PER_MILLION" \
      --argjson output_rate "$CODEX_OUTPUT_COST_PER_MILLION" \
      --argjson cached_rate "$CODEX_CACHED_INPUT_COST_PER_MILLION" '
      (if $cached_tokens > $input_tokens then $input_tokens else $cached_tokens end) as $effective_cached
      | ($input_tokens - $effective_cached) as $effective_uncached
      | (($effective_uncached / 1000000) * $input_rate)
        + (($effective_cached / 1000000) * $cached_rate)
        + (($output_tokens / 1000000) * $output_rate)
    ')
  fi

  # Append stats to JSONL file
  STATS=$(jq -n -c \
    --arg run_id "$RUN_ID" \
    --arg model "$MODEL" \
    --argjson iteration "$i" \
    --argjson duration_ms "$DURATION_MS" \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    --argjson cached_input_tokens "$CACHED_INPUT_TOKENS" \
    --argjson reasoning_output_tokens "$REASONING_OUTPUT_TOKENS" \
    --argjson cost_usd "$COST_USD" \
    '{
      run_id: $run_id,
      engine: "codex",
      iteration: $iteration,
      timestamp: (now | todate),
      duration_ms: $duration_ms,
      model: $model,
      input_tokens: $input_tokens,
      output_tokens: $output_tokens,
      cached_input_tokens: $cached_input_tokens,
      reasoning_output_tokens: $reasoning_output_tokens,
      cost_usd: $cost_usd
    }')

  echo "$STATS" >> "$STATS_FILE"

  # Check for completion signal
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
