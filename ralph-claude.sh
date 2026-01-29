#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop (Claude Code version)
# Usage: ./ralph-claude.sh [max_iterations]
# Requires: Claude Code CLI (https://docs.anthropic.com/en/docs/claude-code)

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
      duration_api_ms: (map(.duration_api_ms // 0) | add),
      total_input: (map(.input_tokens // 0) | add),
      total_output: (map(.output_tokens // 0) | add),
      cache_read: (map(.cache_read_tokens // 0) | add),
      cache_creation: (map(.cache_creation_tokens // 0) | add),
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
  CACHE_READ=$(echo "$SUMMARY" | jq -r '.cache_read')
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

  # Format token counts with commas
  TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT + CACHE_READ))

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo " Ralph Complete!"
  echo "═══════════════════════════════════════════════════════════"
  echo " Engine:        claude"
  echo " Iterations:    $ITERATIONS"
  echo " Duration:      $DURATION_FMT ($DURATION_MS ms)"
  echo " Total Tokens:  $TOTAL_TOKENS (input: $TOTAL_INPUT / output: $TOTAL_OUTPUT / cache: $CACHE_READ)"
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
  
  # Run Claude Code with the ralph prompt
  # Using -p (print mode) for non-interactive execution
  # Using --dangerously-skip-permissions to allow autonomous operation
  # Using --output-format json to capture stats
  OUTPUT=$(claude -p "$(cat "$SCRIPT_DIR/prompt-claude.md")" --dangerously-skip-permissions --output-format json 2>&1) || true

  # Extract result text for display and completion check
  RESULT=$(echo "$OUTPUT" | jq -r '.result // empty' 2>/dev/null || echo "$OUTPUT")
  echo "$RESULT"

  # Extract and append stats to JSONL file
  STATS=$(echo "$OUTPUT" | jq -c '{
    run_id: "'"$RUN_ID"'",
    engine: "claude",
    iteration: '"$i"',
    timestamp: (now | todate),
    duration_ms: .duration_ms,
    duration_api_ms: .duration_api_ms,
    num_turns: .num_turns,
    model: (.modelUsage | keys[0] // "unknown"),
    input_tokens: .usage.input_tokens,
    output_tokens: .usage.output_tokens,
    cache_read_tokens: .usage.cache_read_input_tokens,
    cache_creation_tokens: .usage.cache_creation_input_tokens,
    cost_usd: .total_cost_usd
  }' 2>/dev/null)

  if [ -n "$STATS" ] && [ "$STATS" != "null" ]; then
    echo "$STATS" >> "$STATS_FILE"
  fi

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
