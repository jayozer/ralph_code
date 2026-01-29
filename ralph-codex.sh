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

  # Format token counts
  TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo " Ralph Complete!"
  echo "═══════════════════════════════════════════════════════════"
  echo " Engine:        codex"
  echo " Iterations:    $ITERATIONS"
  echo " Duration:      $DURATION_FMT ($DURATION_MS ms)"
  echo " Total Tokens:  $TOTAL_TOKENS (input: $TOTAL_INPUT / output: $TOTAL_OUTPUT)"
  echo " Total Cost:    \$$COST_FMT"
  echo " Model:         $MODEL"
  echo "═══════════════════════════════════════════════════════════"
}

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"
  
  # Run OpenAI Codex with the ralph prompt
  # Using exec for direct command execution
  # Using --full-auto for autonomous operation (or --yolo for skip confirmations)
  # Using --json to capture stats via JSONL events
  START_TIME=$(date +%s%3N)
  OUTPUT=$(codex exec "$(cat "$SCRIPT_DIR/prompt-codex.md")" --full-auto --json 2>&1) || true
  END_TIME=$(date +%s%3N)
  DURATION_MS=$((END_TIME - START_TIME))

  # Parse JSONL output from Codex
  # Codex outputs multiple JSON lines; extract message content for display
  # and usage stats from completion events
  RESULT=""
  INPUT_TOKENS=0
  OUTPUT_TOKENS=0
  MODEL="unknown"

  while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Try to parse as JSON
    TYPE=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)

    case "$TYPE" in
      "message")
        # Extract message content for display
        MSG=$(echo "$line" | jq -r '.content // empty' 2>/dev/null)
        [ -n "$MSG" ] && RESULT="${RESULT}${MSG}"
        ;;
      "usage"|"completion")
        # Extract token usage
        INPUT=$(echo "$line" | jq -r '.usage.input_tokens // .input_tokens // 0' 2>/dev/null)
        OUTPUT_T=$(echo "$line" | jq -r '.usage.output_tokens // .output_tokens // 0' 2>/dev/null)
        MDL=$(echo "$line" | jq -r '.model // empty' 2>/dev/null)
        [ "$INPUT" != "0" ] && INPUT_TOKENS=$((INPUT_TOKENS + INPUT))
        [ "$OUTPUT_T" != "0" ] && OUTPUT_TOKENS=$((OUTPUT_TOKENS + OUTPUT_T))
        [ -n "$MDL" ] && [ "$MDL" != "null" ] && MODEL="$MDL"
        ;;
      *)
        # For non-JSON or other types, append to result for display
        if ! echo "$line" | jq empty 2>/dev/null; then
          RESULT="${RESULT}${line}\n"
        fi
        ;;
    esac
  done <<< "$OUTPUT"

  # Display the result
  echo -e "$RESULT"

  # Append stats to JSONL file
  STATS=$(jq -n -c \
    --arg run_id "$RUN_ID" \
    --arg model "$MODEL" \
    --argjson iteration "$i" \
    --argjson duration_ms "$DURATION_MS" \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    '{
      run_id: $run_id,
      engine: "codex",
      iteration: $iteration,
      timestamp: (now | todate),
      duration_ms: $duration_ms,
      model: $model,
      input_tokens: $input_tokens,
      output_tokens: $output_tokens,
      cost_usd: null
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
