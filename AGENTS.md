# Ralph Agent Instructions (OpenAI Codex)

## Overview

Ralph is an autonomous AI agent loop that runs OpenAI Codex or Claude Code repeatedly until all PRD items are complete. Each iteration is a fresh agent instance with clean context.

## Commands

```bash
# Run Ralph with Codex (from your project that has prd.json)
./ralph.sh codex [max_iterations]

# Examples:
./ralph.sh codex 10     # OpenAI Codex with 10 iterations
./ralph.sh codex 5      # OpenAI Codex with 5 iterations
./ralph.sh claude 10    # Claude Code with 10 iterations (alternative)
```

## Key Files

- `ralph.sh` - Wrapper script to choose engine (claude/codex)
- `ralph-codex.sh` - OpenAI Codex specific agent loop
- `ralph-claude.sh` - Claude Code specific agent loop
- `prompt-codex.md` - Instructions for Codex iterations
- `prompt-claude.md` - Instructions for Claude Code iterations
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Patterns

- Each iteration spawns a fresh Codex instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations

## Codex-Specific Notes

- Codex reads `AGENTS.md` automatically (like Claude reads `CLAUDE.md`)
- The `prompt-codex.md` file contains iteration-specific instructions
- Codex uses the OpenAI CLI (`codex` command)
