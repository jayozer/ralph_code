# The Built-in Claude Code Ralph Skill "Isn't It" — Here's What Actually Works

**How a simple bash loop outperforms the official implementation**

If you've been on tech Twitter lately, you've seen everyone talking about "Ralph Wiggum" — the autonomous AI coding loop that's replacing entire dev teams. At a Y Combinator hackathon, teams shipped 6 repos overnight. One engineer completed a $50k contract for $297 in API costs.

But here's what most people don't know: the built-in Claude Code ralph skill isn't the real thing.

Geoffrey Huntley, who created the Ralph pattern, has explicitly stated this. In his words: "Claude Code's implementation isn't it."

I've been using the original pattern, converted to work with Claude Code, and the difference is night and day. Here's why.

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
- **CLAUDE.md** — codebase knowledge

This is the key insight: memory should be external, not in-context.

## What I Built: PRD-Driven Ralph for Claude Code

I converted Ryan Carson's Amp implementation to work with Claude Code, and added some enhancements:

### 1. Structured User Stories

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

### 2. Learning Persistence

Each iteration appends discoveries to progress.txt:

```markdown
## Codebase Patterns
- Use sql<number> template for aggregations
- Always use IF NOT EXISTS for migrations

## 2026-01-18 - US-003
- Learnings: Filter state is in URL params, not React state
```

These patterns persist across iterations and across features. Future Ralph instances read this first.

### 3. Browser Verification

For UI stories, Ralph uses Playwright or webapp-testing tools to actually verify changes work. A frontend story isn't complete until it's visually confirmed.

### 4. Full Customization

Every instruction is in prompt.md. Want project-specific rules? Edit the file:

```markdown
## Quality Requirements
- Run npm run typecheck before committing
- Never modify files in src/legacy/
- Always add tests for new utilities
```

## The Results

At the Y Combinator hackathon, teams using this pattern shipped 6 repos overnight. Not prototypes — working software.

One engineer I know completed a $50k contract using Ralph. Total API cost: $297.

The key is structured iteration with verifiable acceptance criteria. Each story is small enough to complete in one context window. Each iteration starts fresh. Each commit is clean.

## Try It Yourself

I've open-sourced my implementation:

**https://github.com/jayozer/ralph_code**

Quick start:

```bash
mkdir -p scripts/ralph
curl -sL https://raw.githubusercontent.com/jayozer/ralph_code/main/ralph.sh > scripts/ralph/ralph.sh
curl -sL https://raw.githubusercontent.com/jayozer/ralph_code/main/prompt.md > scripts/ralph/prompt.md
chmod +x scripts/ralph/ralph.sh
```

Create a prd.json with your user stories, then:

```bash
./scripts/ralph/ralph.sh 10
```

Watch it implement your feature while you sleep.

## The Bottom Line

If you want a quick and dirty loop — use the built-in skill.

If you want full control, fresh context, PRD-driven workflow, and persistent learning — use the original pattern.

As Geoffrey Huntley puts it: *"That's the beauty of Ralph — the technique is deterministically bad in an undeterministic world."*

The built-in skill tries to be smart. The original pattern is deliberately simple. And simple wins.

*Every failure leaves a breadcrumb. Every small commit adds a brick. Eventually, the breadcrumbs become a highway and the bricks become a cathedral. Ralph just keeps laying bricks.*

---

**Credits:** Geoffrey Huntley (created the pattern), Ryan Carson (original Amp implementation), Claude Code (the AI that does the work).
