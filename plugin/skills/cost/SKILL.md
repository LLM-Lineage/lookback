---
name: cost
description: Show where tokens and tool calls actually went, attributed to the skill, subagent, plugin and tool that spent them. Use when the user asks what is expensive, which skill or agent is burning context, where their usage goes, or says /lookback:cost.
---

# Where the effort went

```sh
lookback collect && lookback cost --json
```

## What makes this trustworthy

Claude Code stamps every transcript record with `attributionSkill`,
`attributionAgent` and `attributionPlugin`, and every assistant message with its
own token usage. Attribution is therefore **recorded, not estimated** — Lookback
is not guessing which skill spent the tokens.

## Reading the numbers

`input_tokens` and `output_tokens` are what was billed as new work.
`cache_read_tokens` is usually far larger than both and costs a fraction; a high
ratio of `cache_creation` to `cache_read` means context is being rebuilt rather
than reused, which is worth mentioning when it stands out.

`tools`, `skills` and `agents` are ordered by call count, each with the tokens
behind it. A skill near the top is the hot path. A subagent with few calls but
heavy tokens is doing expensive work per invocation, which is a different
problem from one that is merely used often.

## Rules

This section is orientation, not advice: it names no change, so do not invent
one. If the user wants recommendations, `lookback report` is where findings live.

State the window the numbers cover — `first_seen` to `last_seen`. A total with
no window is a number nobody can act on.
