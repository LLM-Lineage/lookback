---
name: review
description: Collect and report everything this machine's Claude Code history says about the user's setup, in one pass, ending with what to improve in priority order. Use when the user asks for a full review of their Claude Code configuration, wants everything at once rather than one area, or says /lookback:review.
---

# The whole picture, in one pass

```sh
lookback review --json
```

One command: it collects first (incremental, so fast after the first run), then
reports every finding, ordered by how much of the user's activity each covers.

## Presenting it

Lead with the finding at the top — the list is already ordered by weight. For
each, give the **change** first and the evidence second. Close with the
`What to improve` grouping: the areas, heaviest first. That last part is what a
reader takes away if they stop halfway.

Findings carry `improves`, one of:

| | |
|---|---|
| `rules` | permission rules and CLAUDE.md |
| `context` | what the repository tells a session before it starts |
| `subagents` | which agent gets delegated to |
| `effort` | the model and reasoning effort left set |
| `skills` | which skills exist and how they are described |
| `explore` | plugins worth trying |

## Scope

This covers every project on the machine. For one repository — which is where
`context` findings become actionable — use `/lookback:repo` instead.

## Rules

**Never apply a change yourself.** Hand over the text; let the user paste it.
Do not edit `settings.json`, `CLAUDE.md` or plugin configuration off a finding.

**Quote the evidence.** Each finding carries counts so the user can disagree.

**Do not inflate.** An empty `findings` list means say so. A finding that does
not fire is information: `effort-overkill` staying silent means the effort
settings match the work, which is worth stating plainly rather than padding.
