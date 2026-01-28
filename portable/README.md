# Ralph - Portable Setup

Copy this entire folder to any project to run Ralph.

## What's Included

```
portable/
├── ralph.sh           # The bash loop (core)
├── prompt.md          # Instructions for Claude (core)
├── prd.json.example   # Example PRD format
├── setup.sh           # One-command project setup
├── install-skills.sh  # Install /prd and /ralph skills globally
├── skills/
│   ├── prd/           # /prd skill for generating PRDs
│   └── ralph/         # /ralph skill for converting to JSON
└── README.md          # This file
```

## Quick Setup

```bash
# 1. Copy this folder to your project
cp -r /path/to/ralph/portable /your-project/ralph

# 2. Make executable
chmod +x /your-project/ralph/ralph.sh

# 3. Create your prd.json (copy and edit the example)
cp /your-project/ralph/prd.json.example /your-project/ralph/prd.json

# 4. Edit prd.json with your user stories

# 5. Run Ralph
cd /your-project/ralph
./ralph.sh 10
```

## Or Use the Setup Script

```bash
# From your project root
/path/to/ralph/portable/setup.sh
```

This creates a `ralph/` folder in your current directory with everything ready.

## Files Included

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh Claude Code instances |
| `prompt.md` | Instructions for each iteration (customize for your project) |
| `prd.json.example` | Example PRD format to copy and edit |
| `setup.sh` | One-command setup script |

## After Setup

1. Edit `prd.json` with your feature's user stories
2. Customize `prompt.md` with project-specific quality rules
3. Run `./ralph.sh 10` to start (10 = max iterations)

## Example prd.json

```json
{
  "project": "YourProject",
  "branchName": "ralph/your-feature",
  "description": "What you're building",
  "userStories": [
    {
      "id": "US-001",
      "title": "First small task",
      "description": "As a user, I want X so that Y.",
      "acceptanceCriteria": [
        "Specific verifiable criterion",
        "Another criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Optional: Install Skills Globally

The `/prd` and `/ralph` skills help you create PRDs interactively. Install once, use in any project:

```bash
./install-skills.sh
```

This installs to `~/.claude/skills/` so you can use:
- `/prd Add user authentication` — Generates a structured PRD
- `/ralph convert tasks/prd-auth.md` — Converts PRD to prd.json

## Tips

- **Keep stories small** — Each must complete in one context window
- **Order by dependency** — Database → Backend → UI
- **Verifiable criteria** — "Button shows modal" not "Good UX"
- **Always include** — "Typecheck passes" on every story
- **UI stories** — Add "Verify in browser" as criterion
