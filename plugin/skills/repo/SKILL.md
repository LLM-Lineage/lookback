---
name: repo
description: Review this repository specifically - what its sessions kept getting wrong, what belongs in its CLAUDE.md or .claude/ so the next session and the rest of the team start with it, and which permission rules and effort settings suit the work done here. Use when the user asks what this project should tell Claude, what to put in CLAUDE.md, why sessions here keep struggling, or says /lookback:repo.
---

# What this repository should be telling every session

```sh
lookback review --repo --json
```

The output covers every session source present on this machine: Claude Code
and OMP. It is `{"reports": [...], "skipped": [...]}`. Each report carries
`source` (`claude` or `omp`), `scope`, `totals` and `findings`; `skipped` names each source left out and
why (nothing collected, or no sessions in scope). Present each source under its
own heading and never merge their counts. OMP findings belong in `AGENTS.md`;
they are never Claude Code permission rules. Pass `--source claude` or
`--source omp` to read one alone, which returns a single bare report.

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
**If `lookback` is not on `PATH`, do not improvise.** `lookback: command not found`
means one specific thing: a repository has declared this plugin in its
`.claude/settings.json`, and this machine has never installed the binary. A settings
file carries the plugin; it cannot carry an executable. Hand over the one line that
fixes it and stop there:

```sh
curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback/main/install.sh | sh
```

Do not build it from source, and do not install anything named `lookback` from a
package registry — that name belongs to a different project by somebody else.

**If the command prints an update notice on stderr, pass it on.** It names the
running version, the newer one and the command. Say it once, plainly, and carry on
with the answer the user asked for — it is a courtesy, not a finding, and not a
reason to stop. Do not run the update yourself: `lookback self-update` and the
installer replace a binary, which is the user's call.


**Never apply a change yourself — use the command instead.** When the user has
read a line and asked for it, do not reach for `Edit` on their memory file:

```sh
lookback remember --write --text "<the exact line they agreed>"
lookback remember --write --global --text "..."   # ~/.claude/CLAUDE.md
lookback remember --write --agents --text "..."   # OMP's AGENTS.md
```

It appends under a heading of its own, never rewrites or removes anything
already there, refuses a duplicate word for word, and copies the file first when
git does not track it. Without `--write` it prints what it would do.

Deciding the words is still yours; placing them is not. Show the exact text,
say which file it lands in and that every session afterwards will act on it, and
run the command only once they have agreed to that line. A finding is never
authorization on its own.

**Say when a finding is thin.** A repository with few sessions will produce weak
evidence. Two sessions is not a pattern; say so rather than dressing it up.
