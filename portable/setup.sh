#!/bin/bash
# Ralph Setup Script
# Run this from your project root to set up Ralph

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-ralph}"

echo "Setting up Ralph in ./$TARGET_DIR/"

# Create target directory
mkdir -p "$TARGET_DIR"

# Copy files
cp "$SCRIPT_DIR/ralph.sh" "$TARGET_DIR/"
cp "$SCRIPT_DIR/prompt.md" "$TARGET_DIR/"
cp "$SCRIPT_DIR/prd.json.example" "$TARGET_DIR/"

# Make executable
chmod +x "$TARGET_DIR/ralph.sh"

echo ""
echo "Done! Ralph is ready in ./$TARGET_DIR/"
echo ""
echo "Next steps:"
echo "  1. cp $TARGET_DIR/prd.json.example $TARGET_DIR/prd.json"
echo "  2. Edit $TARGET_DIR/prd.json with your user stories"
echo "  3. (Optional) Edit $TARGET_DIR/prompt.md for project-specific rules"
echo "  4. cd $TARGET_DIR && ./ralph.sh 10"
echo ""
