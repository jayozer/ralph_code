#!/bin/bash
# Ralph Stats Monitor - View stats for current or recent runs
# Usage: ./ralph-stats.sh [watch]
#   watch - Auto-refresh every 5 seconds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATS_FILE="$SCRIPT_DIR/ralph-stats.jsonl"

show_stats() {
  if [ ! -f "$STATS_FILE" ]; then
    echo "No stats file found. Run Ralph first."
    return 1
  fi

  # Get the latest run
  LATEST=$(jq -s 'group_by(.run_id) | last' "$STATS_FILE" 2>/dev/null)

  if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
    echo "No stats data found."
    return 1
  fi

  RUN_ID=$(echo "$LATEST" | jq -r '.[0].run_id')
  ENGINE=$(echo "$LATEST" | jq -r '.[0].engine')
  ITERATIONS=$(echo "$LATEST" | jq 'length')

  # Calculate totals
  DURATION_MS=$(echo "$LATEST" | jq '[.[].duration_ms // 0] | add')
  INPUT_TOKENS=$(echo "$LATEST" | jq '[.[].input_tokens // 0] | add')
  OUTPUT_TOKENS=$(echo "$LATEST" | jq '[.[].output_tokens // 0] | add')
  CACHE_READ=$(echo "$LATEST" | jq '[.[].cache_read_tokens // 0] | add')
  COST=$(echo "$LATEST" | jq '[.[].cost_usd // 0] | add')
  MODEL=$(echo "$LATEST" | jq -r '.[0].model // "unknown"')

  # Get first timestamp and calculate elapsed time
  FIRST_TS=$(echo "$LATEST" | jq -r '.[0].timestamp')
  LAST_TS=$(echo "$LATEST" | jq -r '.[-1].timestamp')

  # Calculate elapsed since run started (wall clock time from first iteration)
  if [ -n "$FIRST_TS" ] && [ "$FIRST_TS" != "null" ]; then
    # Parse ISO timestamp to epoch
    FIRST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$FIRST_TS" +%s 2>/dev/null || date -d "$FIRST_TS" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    ELAPSED_SEC=$((NOW_EPOCH - FIRST_EPOCH))
    ELAPSED_MIN=$((ELAPSED_SEC / 60))
    ELAPSED_SEC_REM=$((ELAPSED_SEC % 60))
    ELAPSED_FMT="${ELAPSED_MIN}m ${ELAPSED_SEC_REM}s"
  else
    ELAPSED_FMT="unknown"
  fi

  # Format duration (API time)
  DURATION_SEC=$((DURATION_MS / 1000))
  DURATION_MIN=$((DURATION_SEC / 60))
  DURATION_SEC_REM=$((DURATION_SEC % 60))
  if [ "$DURATION_MIN" -gt 0 ]; then
    DURATION_FMT="${DURATION_MIN}m ${DURATION_SEC_REM}s"
  else
    DURATION_FMT="${DURATION_SEC}s"
  fi

  # Format cost
  COST_FMT=$(printf "%.2f" "$COST")

  # Calculate total tokens
  TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS + CACHE_READ))

  # Clear screen for watch mode
  [ "$1" = "clear" ] && clear

  echo "═══════════════════════════════════════════════════════════"
  echo " Ralph Stats Monitor"
  echo "═══════════════════════════════════════════════════════════"
  echo " Run ID:        $RUN_ID"
  echo " Engine:        $ENGINE"
  echo " Model:         $MODEL"
  echo "───────────────────────────────────────────────────────────"
  echo " Iterations:    $ITERATIONS"
  echo " Elapsed:       $ELAPSED_FMT (wall clock)"
  echo " API Time:      $DURATION_FMT ($DURATION_MS ms)"
  echo "───────────────────────────────────────────────────────────"
  echo " Input Tokens:  $INPUT_TOKENS"
  echo " Output Tokens: $OUTPUT_TOKENS"
  if [ "$CACHE_READ" -gt 0 ]; then
    echo " Cache Read:    $CACHE_READ"
  fi
  echo " Total Tokens:  $TOTAL_TOKENS"
  echo "───────────────────────────────────────────────────────────"
  if [ "$ENGINE" = "claude" ]; then
    echo " Total Cost:    \$$COST_FMT"
  else
    echo " Total Cost:    N/A (Codex)"
  fi
  echo "═══════════════════════════════════════════════════════════"
  echo " Last updated:  $(date '+%H:%M:%S')"
}

# Check for watch mode
if [ "$1" = "watch" ] || [ "$1" = "-w" ]; then
  echo "Watching stats (Ctrl+C to stop)..."
  sleep 1
  while true; do
    show_stats clear
    sleep 5
  done
else
  show_stats
fi
