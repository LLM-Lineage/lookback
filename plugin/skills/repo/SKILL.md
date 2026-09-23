---
name: repo
description: Review this repository specifically - what its sessions kept getting wrong, what belongs in its CLAUDE.md or .claude/ so the next session and the rest of the team start with it, and which permission rules and effort settings suit the work done here. Use when the user asks what this project should tell Claude, what to put in CLAUDE.md, why sessions here keep struggling, or says /lookback:repo.
---

# What this repository should be telling every session

```sh
lookback review --repo --json
```

`--repo` with no value means "the repository this is running in", resolved from
`$CLAUDE_PROJECT_DIR`. Every finding is then scoped to sessions whose working
directory is at or below that path.

## The finding that only makes sense here

**`relearned-each-session`** is the reason this mode exists. It looks for
commands that *failed and then succeeded inside the same session*, repeatedly
across sessions. That shape means the model worked out the right form, used it,
and lost it — because the answer lives in a transcript instead of in the
repository. Every repetition is the same discovery, paid for again.

Its `actions` carry both halves where the store has them: the form that failed
and the form that worked. That pair is what belongs in `CLAUDE.md`, because it
is the part the next session cannot derive.

Generic shell utilities are excluded on purpose. `cat /tmp/report.md` failing
means a file was not there, not that anyone needs to write it down.

## Turning findings into repository context

Sort what you find into where it belongs:

- **`CLAUDE.md`** — standing facts and preferences: the command that works, the
  thing never to run here, the convention every session should assume.
- **`.claude/settings.json`** — permission rules for this project, so they apply
  to everyone who clones it rather than living in one person's user settings.
- **A skill** — anything that is a *procedure* rather than a fact. A procedure
  retyped is a skill that does not exist yet.

The distinction that matters: a fact goes in `CLAUDE.md`, a permission goes in
settings, a procedure becomes a skill.

## Rules

**Propose; do not write.** Especially here. These files are shared with everyone
working in the repository, so a wrong line costs more than one person's time.
Show the exact text and the observation behind it, and let the user commit it.

**Say when a finding is thin.** A repository with few sessions will produce weak
evidence. Two sessions is not a pattern; say so rather than dressing it up.
