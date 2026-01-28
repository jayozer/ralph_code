#!/bin/bash
# Install Ralph skills globally for Claude Code
# These enable /prd and /ralph commands in any Claude Code session

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

echo "Installing Ralph skills to $SKILLS_DIR/"

mkdir -p "$SKILLS_DIR"

# Copy skills
cp -r "$SCRIPT_DIR/skills/prd" "$SKILLS_DIR/"
cp -r "$SCRIPT_DIR/skills/ralph" "$SKILLS_DIR/"

echo ""
echo "Done! Skills installed:"
echo "  /prd   - Generate a PRD from a feature description"
echo "  /ralph - Convert a PRD to prd.json format"
echo ""
echo "Usage:"
echo "  /prd Add a task priority system with high/medium/low levels"
echo "  /ralph convert tasks/prd-task-priority.md"
echo ""
