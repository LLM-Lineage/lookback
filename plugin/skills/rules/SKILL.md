---
name: rules
description: Suggest permission rules and CLAUDE.md entries drawn from what actually happened in past sessions - commands that prompt constantly with no allow rule, commands the model keeps retrying that the user's own deny rules block, and instructions retyped across sessions. Use when the user asks which permission rules to add, why they keep being asked to approve things, what belongs in CLAUDE.md, or says /lookback:rules.
---

# Permission rules and CLAUDE.md entries worth adding

```sh
lookback collect && lookback rules --json
```

Add `--repo` to scope this to the current repository — rules that belong in the
project's own `.claude/settings.json` rather than the user's.

Three findings land here, and they have different fixes.

## `unruled-bash`

Command prefixes that ran often with no `permissions.allow` rule covering them —
every one was a prompt answered by hand. The `actions` list is ready to paste
into `permissions.allow`.

The finding inverts when a bare `Bash` entry already allows everything: then the
useful advice is to replace that blanket allow with explicit prefixes, which
keeps the prompts away while narrowing what an unattended session can reach.

## `retried-denied-command`

Commands that fail because the user's *own* `deny` rules block them. The model
cannot see permission rules, so it keeps reaching for them and keeps being
refused. The fix is not a permission change — it is writing the restriction, and
the alternative, into `CLAUDE.md`.

## `repeated-prompt`

Instructions retyped across separate sessions. Something explained more than
twice is a standing preference, and a preference belongs in configuration rather
than in the user's typing. Spanning several projects means the user's
`~/.claude/CLAUDE.md`; confined to one means that project's.

Anything that is a *procedure* rather than a preference is a skill: it gets
invoked by name instead of retyped.

## Rules

Hand the user the text; do not edit their configuration yourself. Show which
observation produced each suggestion, so a rule they disagree with is one they
can reject rather than one that silently appears.
