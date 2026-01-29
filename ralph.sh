#!/bin/bash
# Ralph - Multi-engine AI agent loop
# Usage: ./ralph.sh [claude|codex] [max_iterations]
#
# Supported engines:
#   claude - Claude Code CLI (default)
#   codex  - OpenAI Codex CLI
#
# Example:
#   ./ralph.sh claude 10
#   ./ralph.sh codex 5

ENGINE="${1:-claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If first arg is a number, treat it as max_iterations with default engine
if [[ "$ENGINE" =~ ^[0-9]+$ ]]; then
  exec "$SCRIPT_DIR/ralph-claude.sh" "$ENGINE"
fi

# Shift engine arg, pass remaining args to engine script
shift 2>/dev/null || true

case "$ENGINE" in
  claude)
    exec "$SCRIPT_DIR/ralph-claude.sh" "$@"
    ;;
  codex)
    exec "$SCRIPT_DIR/ralph-codex.sh" "$@"
    ;;
  -h|--help|help)
    echo "Ralph - Multi-engine AI agent loop"
    echo ""
    echo "Usage: ./ralph.sh [engine] [max_iterations]"
    echo ""
    echo "Engines:"
    echo "  claude  - Claude Code CLI (default)"
    echo "  codex   - OpenAI Codex CLI"
    echo ""
    echo "Examples:"
    echo "  ./ralph.sh              # Claude with default 10 iterations"
    echo "  ./ralph.sh 5            # Claude with 5 iterations"
    echo "  ./ralph.sh claude 10    # Claude with 10 iterations"
    echo "  ./ralph.sh codex 10     # Codex with 10 iterations"
    exit 0
    ;;
  *)
    echo "Unknown engine: $ENGINE"
    echo "Usage: ./ralph.sh [claude|codex] [max_iterations]"
    echo "Run './ralph.sh --help' for more info"
    exit 1
    ;;
esac
