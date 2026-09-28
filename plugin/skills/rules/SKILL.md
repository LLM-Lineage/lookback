---
name: rules
description: Suggest permission rules and CLAUDE.md entries drawn from what actually happened in past sessions - commands that prompt constantly with no allow rule, commands the model keeps retrying that the user's own deny rules block, and instructions retyped across sessions. Use when the user asks which permission rules to add, why they keep being asked to approve things, what belongs in CLAUDE.md, or says /lookback:rules.
---

# Permission rules and CLAUDE.md entries worth adding

```sh
lookback collect && lookback rules --json
```

The output covers every session source present on this machine: Claude Code
and OMP. It is `{"reports": [...], "skipped": [...]}`. Each report carries
`source` (`claude` or `omp`), `scope`, `totals` and `findings`; `skipped` names each source left out and
why (nothing collected, or no sessions in scope). Present each source under its
own heading and never merge their counts. OMP findings belong in `AGENTS.md`;
they are never Claude Code permission rules. Pass `--source claude` or
`--source omp` to read one alone, which returns a single bare report.

Add `--repo` to scope this to the current repository — rules that belong in the
project's own `.claude/settings.json` rather than the user's.

Three findings land here, and they have different fixes.

## The permission rules can be applied for them

```sh
lookback rules --write            # this repository's .claude/settings.json
lookback rules --write --global   # the user's ~/.claude/settings.json
```

**Offer this instead of editing the file yourself.** It is the same merge
`install` uses — everything already there is preserved, including key order —
and it is deterministic and tested, where you pasting JSON is neither. It only
ever adds to `permissions.allow`, never touches `deny` or `ask`, and copies the
file first when git does not track it.

Two things to tell them when it applies:

- If the output says the additions **will not change anything yet**, a blanket
  `Bash` is allowing everything already. `--narrow` removes it, and that is a
  real decision: every command the new rules do not name starts prompting again.
  Say that before suggesting it.
- If the blanket is in a different file from the one being written — a user-level
  `Bash` while a repository's settings are updated — nothing in that repository
  can remove it. It has to be narrowed where it lives.

This covers the permission rules only. Everything below that belongs in
`CLAUDE.md` is still yours to propose and theirs to paste.

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

Instructions the user keeps retyping. **The point of every one is to stop typing
it**, so the line you propose is the one that makes it happen unprompted.

Write that line first, for every cluster, and only fall back to anything else
for the exception below. Do not deliberate about which kind each one is — on a
real corpus nine of ten wanted the proactive form and none wanted a verbatim
transcription.

### The mistake this finding is most likely to produce

It has already happened to a customer, in this exact shape. Lookback reported
that "commit and push" had been typed many times, and the line written back was:

> When I explicitly ask you to commit and push, commit the requested changes and
> push the resulting branch. Do not treat this preference as permission to commit
> or push without an explicit request.

Faithful to what was typed, already true, and it left them asking every time.
Their reply:

> wait, why is this the correct fix? I want you to save me time so I would have
> expected you to put in an instruction that proactively commits and pushes

The line that should have been offered first:

> After completing a coding task, proactively commit the changes you made and
> push the branch without waiting for a separate request. Follow the repository's
> branch and contribution rules; never push to a protected branch. Do not include
> unrelated changes in the commit.

The repetition was never about *how to respond when asked*. It was about **being
asked at all**.

### The test

Read your proposed line back and ask: **would the user still type the original
prompt?** If yes, you have recorded the request instead of removing it. Rewrite
it.

### The exception

A prompt that states a rule rather than asks for something — "never force-push",
"prefer table-driven tests" — is already in the right form and goes in as
written. This is the minority. A prompt that begins with a verb is almost never
one of these.

Some clusters are neither: a probe typed to check the agent is alive, a task
that happened to recur. Say so and drop them rather than inventing a rule.

### Scope, which is not optional

A standing instruction grants standing authority. Say plainly what it would let
happen without asking, and how widely — a line in `~/.claude/CLAUDE.md` applies
to every repository on the machine — and get explicit agreement to that scope
before the user pastes it. This matters most for exactly the lines worth
proposing: committing, pushing, deploying, spending. Narrow where you can
("follow the repository's own branch rules; never push to a protected branch")
rather than offering blanket permission.

Spanning several projects means `~/.claude/CLAUDE.md`; confined to one means
that project's. Anything that is a *procedure* rather than an instruction is a
skill: it gets invoked by name instead of retyped.

## Rules

Show which observation produced each suggestion and offer the exact text, so a
rule the user disagrees with is one they can reject rather than one that
silently appears.

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
