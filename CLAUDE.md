# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs Claude Code or OpenAI Codex repeatedly until all PRD items are complete. Each iteration is a fresh agent instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph (from your project that has prd.json)
./ralph.sh [claude|codex] [max_iterations]

# Examples:
./ralph.sh claude 10    # Claude Code with 10 iterations
./ralph.sh codex 5      # OpenAI Codex with 5 iterations
./ralph.sh 10           # Claude Code (default) with 10 iterations
```

## Key Files

- `ralph.sh` - Wrapper script to choose engine (claude/codex)
- `ralph-claude.sh` - Claude Code specific agent loop
- `ralph-codex.sh` - OpenAI Codex specific agent loop
- `prompt-claude.md` - Instructions for Claude Code iterations
- `prompt-codex.md` - Instructions for Codex iterations
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works
- `.claude/skills/` - Claude Code skills for PRD generation and conversion

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh Claude Code instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update CLAUDE.md with discovered patterns for future iterations
