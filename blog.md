# The Built-in Claude Code Ralph Skill "Isn't It" — Here's What Actually Works

**How a simple bash loop outperforms the official implementation**

If you've been on tech Twitter lately, you've seen everyone talking about "Ralph Wiggum" — the autonomous AI coding loop that's replacing entire dev teams. At a Y Combinator hackathon, teams shipped 6 repos overnight. One engineer completed a $50k contract for $297 in API costs.

But here's what most people don't know: the built-in Claude Code ralph skill isn't the real thing.

Geoffrey Huntley, who created the Ralph pattern, has explicitly stated this. In his words: "Claude Code's implementation isn't it."

I've been using the original pattern, converted to work with Claude Code and OpenAI Codex, and the difference is night and day. Here's why — and how you can use it in your own projects.

## The Problem with the Built-in Skill

The built-in ralph skill uses a Stop hook that blocks Claude Code from exiting. When Claude tries to finish, the hook intercepts and feeds the same prompt back in. Sounds clever, right?

The problem: context accumulates.

Each iteration builds on the same session. The context window fills up. By iteration 10, Claude is swimming in its own previous outputs, struggling to focus on the actual task. Quality degrades. Code gets sloppy.

```
Iteration 1: Fresh context, clean code
Iteration 5: Context filling, still okay
Iteration 10: Context overloaded, quality drops
Iteration 15: Hallucinations, broken commits
```

## The Original Pattern: Fresh Context Every Time

Geoffrey's original Ralph is beautifully simple:

```bash
while :; do cat PROMPT.md | claude-code ; done
```

Each iteration spawns a fresh Claude Code instance. No accumulated context. No degradation. The only memory between iterations is external:

- **Git history** — what was done
- **prd.json** — what's left to do
- **progress.txt** — learnings and patterns
- **CLAUDE.md / AGENTS.md** — codebase knowledge

This is the key insight: memory should be external, not in-context.

## What I Built: PRD-Driven Ralph

I converted Ryan Carson's Amp implementation to work with both Claude Code and OpenAI Codex. Here's what makes it powerful:

### Multi-Engine Support

Choose your AI engine:

```bash
./ralph.sh claude 10    # Claude Code with 10 iterations
./ralph.sh codex 10     # OpenAI Codex with 10 iterations
```

Same workflow, same PRD format, different engine. Each has its own prompt file (`prompt-claude.md` or `prompt-codex.md`) that you can customize.

### Structured User Stories

Instead of a vague prompt, you define exactly what "done" looks like:

```json
{
  "id": "US-001",
  "title": "Add priority filter",
  "acceptanceCriteria": [
    "Filter dropdown with options: All | High | Medium | Low",
    "Filter persists in URL params",
    "Typecheck passes",
    "Verify in browser"
  ],
  "passes": false
}
```

Ralph picks the highest priority story, implements it, runs quality checks, commits, marks it done, and exits. Next iteration picks up the next story.

### Learning Persistence

Each iteration appends discoveries to progress.txt:

```markdown
## Codebase Patterns
- Use sql<number> template for aggregations
- Always use IF NOT EXISTS for migrations

## 2026-01-18 - US-003
- Learnings: Filter state is in URL params, not React state
```

These patterns persist across iterations and across features. Future Ralph instances read this first.

### Browser Verification

For UI stories, Ralph uses Playwright or webapp-testing tools to actually verify changes work. A frontend story isn't complete until it's visually confirmed.

### Full Customization

Every instruction is in `prompt-claude.md` (or `prompt-codex.md`). Want project-specific rules? Edit the file:

```markdown
## Quality Requirements
- Run npm run typecheck before committing
- Never modify files in src/legacy/
- Always add tests for new utilities
```

## How to Use Ralph in Your Workflow

Here's the complete workflow from feature idea to shipped code:

### Step 1: Get the Files

```bash
# Clone the repo
git clone https://github.com/jayozer/ralph.git

# Copy to your project
cp ralph/ralph.sh ralph/ralph-claude.sh ralph/prompt-claude.md ralph/prd.json.example /path/to/your-project/
chmod +x /path/to/your-project/ralph*.sh
```

Or download directly:

```bash
cd /path/to/your-project
curl -sLO https://raw.githubusercontent.com/jayozer/ralph/main/ralph.sh
curl -sLO https://raw.githubusercontent.com/jayozer/ralph/main/ralph-claude.sh
curl -sLO https://raw.githubusercontent.com/jayozer/ralph/main/prompt-claude.md
curl -sLO https://raw.githubusercontent.com/jayozer/ralph/main/prd.json.example
chmod +x ralph*.sh
```

### Step 2: Create Your PRD

Copy the example and edit it with your user stories:

```bash
cp prd.json.example prd.json
```

**Tips for good stories:**
- Each story should complete in ONE iteration (one context window)
- Order by dependency: schema → backend → UI
- Always include "Typecheck passes" in acceptance criteria
- Add "Verify in browser" for UI stories

### Step 3: Run Ralph

```bash
./ralph.sh claude 10   # Run 10 iterations with Claude Code
```

Ralph will:
1. Create/switch to the branch specified in `prd.json`
2. Pick the highest-priority incomplete story
3. Implement it and run quality checks
4. Commit changes and mark the story as `passes: true`
5. Log learnings to `progress.txt`
6. Repeat until done

### Step 4: Monitor and Review

```bash
# Watch progress
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings
cat progress.txt

# Review commits
git log --oneline -10
```

## Bonus: PRD Generation Skills (Claude Code Only)

I've included two Claude Code skills that streamline the workflow even further:

### `/prd` — Generate a PRD from an idea

```
/prd Add a task priority system with high/medium/low levels
```

The skill asks clarifying questions, then generates a structured PRD in `tasks/prd-[feature-name].md`.

### `/ralph` — Convert PRD to JSON

```
/ralph convert tasks/prd-task-priority.md
```

Converts your PRD markdown into the `prd.json` format Ralph executes.

**Install the skills:**

```bash
mkdir -p ~/.claude/skills
cp -r /path/to/ralph/.claude/skills/prd ~/.claude/skills/
cp -r /path/to/ralph/.claude/skills/ralph ~/.claude/skills/
```

## The Results

At the Y Combinator hackathon, teams using this pattern shipped 6 repos overnight. Not prototypes — working software.

One engineer I know completed a $50k contract using Ralph. Total API cost: $297.

The key is structured iteration with verifiable acceptance criteria. Each story is small enough to complete in one context window. Each iteration starts fresh. Each commit is clean.

## Try It Yourself

I've open-sourced my implementation:

**https://github.com/jayozer/ralph**

Quick start:

```bash
# Get the files
git clone https://github.com/jayozer/ralph.git
cp ralph/ralph.sh ralph/ralph-claude.sh ralph/prompt-claude.md ralph/prd.json.example ./

# Create your PRD
cp prd.json.example prd.json
# Edit prd.json with your user stories

# Run Ralph
chmod +x ralph*.sh
./ralph.sh claude 10
```

Watch it implement your feature while you sleep.

## The Bottom Line

If you want a quick and dirty loop — use the built-in skill.

If you want full control, fresh context, PRD-driven workflow, and persistent learning — use the original pattern.

**What's new in this version:**
- Multi-engine support (Claude Code + OpenAI Codex)
- Separate prompt files for each engine
- PRD generation skills (`/prd` and `/ralph`)
- Cleaner file structure — just copy what you need
- AGENTS.md support for OpenAI Codex projects

As Geoffrey Huntley puts it: *"That's the beauty of Ralph — the technique is deterministically bad in an undeterministic world."*

The built-in skill tries to be smart. The original pattern is deliberately simple. And simple wins.

*Every failure leaves a breadcrumb. Every small commit adds a brick. Eventually, the breadcrumbs become a highway and the bricks become a cathedral. Ralph just keeps laying bricks.*

---

**Credits:** Geoffrey Huntley (created the pattern), Ryan Carson (original Amp implementation), Claude Code & OpenAI Codex (the AIs that do the work).
