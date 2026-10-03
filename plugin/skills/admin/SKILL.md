---
name: admin
description: Show what Lookback changed in the user's Claude Code configuration without being asked, the evidence behind each change, and anything waiting for a decision - then approve, refuse or undo. Use when the user asks what Lookback did, why a permission rule appeared, wants to undo a change, asks about pending or queued changes, or says /lookback:admin.
---

# What Lookback did, and what is waiting

Lookback runs when a session ends. It snapshots the configuration, applies the
changes that only remove a prompt the user was already answering, and queues
everything that would grant new authority. This is where all of it is visible.

```sh
lookback admin --json
```

## What comes back

- `changes` — newest first. Each carries `summary`, `path`, `evidence`, `tier`,
  `state` (`proposed` / `applied` / `rejected`), and `reversed_by` when it has
  been undone.
- `trusted` — kinds of change the user has approved often enough that Lookback
  stops asking, with `approvals`, `rejections` and `automatic`.
- `threshold` — how many approvals that takes.

## The two tiers, because the answer to "why did this appear" differs

`tier: "friction"` was applied without asking. Every call it covers had already
run, and Claude Code prompts before running — so it was approved by hand, many
times, and the rule removes the keystroke rather than a safeguard.

`tier: "authority"` is waiting, and the honest answer to "why is this waiting"
is in the change itself: it would grant standing permission that does not exist
yet. Anything that belongs in a memory file is here too, because what to write,
in which file and in which words is judgement.

## Acting on one

```sh
lookback admin approve <id>    # apply it, and count it toward trusting its kind
lookback admin reject <id>     # refuse it, and stop it being offered
lookback admin rollback <id>   # put the file back to what it held
lookback admin show <id>       # the evidence and both versions of the file
```

An undo is recorded as a new change rather than an edit to the old one, so the
history says what happened and then what happened next.

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

It matters more here than in the other skills. Without the binary there is no
`SessionEnd` hook, so nothing has been changed and nothing is waiting — the right
answer is "it has not been installed", not "it has done nothing for you".

**Lead with the evidence, every time.** A change the user cannot check is one
they should not accept, and here that matters more than anywhere else in
Lookback: these are changes to their files that nobody asked for. "`git status`
ran 563 times with no rule covering it" is what makes the rule reasonable.

**Never approve or reject on the user's behalf.** The queue exists because those
changes need a person. Presenting one and picking for them defeats the only
safeguard in the design. Show what is waiting and what each would permit, and
let them answer.

**Say plainly what a queued change would allow.** A standing instruction grants
standing authority. If a change would let a session commit, push, deploy or
spend without asking, say that in those words before the user decides.

**A refused rollback is information, not an error to retry.** `rollback` stops
when the file has changed since, because undoing it would discard that edit.
Relay the message and let the user decide; do not write the file yourself.

**If `changes` is empty, say so.** It means the loop has not run or found
nothing. Inventing something to show teaches the user to stop reading this.
