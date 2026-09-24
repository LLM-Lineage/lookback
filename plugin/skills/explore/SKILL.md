---
name: explore
description: Suggest Claude Code plugins to explore, matched offline against the locally cached marketplace catalogue using what the user actually spends time on. Use when the user asks what plugins they should try, what else might help their workflow, what is available for their stack, or says /lookback:explore.
---

# Plugins worth trying

```sh
lookback collect && lookback explore --json
```

## How the match is made

A usage signature is built from the command prefixes that appear most in the
user's history, with generic shell utilities excluded — `grep` and `cat` are the
most frequent commands on any machine and say nothing about what someone works
on. What is left is the ecosystem: `cargo`, `gh`, `terraform`, `aws`, `npm`.

Those terms are matched as **whole words** against the plugin catalogue already
cached on this machine, skipping anything already enabled, and ranked by how
many people have installed it.

## Two things to say plainly

**Nothing was fetched and nothing was sent.** The catalogue is a file that was
already on disk. Exploring plugins does not tell anyone what the user works on.

**These are suggestions to look at, not installations.** Lookback installs
nothing, and neither should you. Give the user the names and what prompted each,
and let them decide.

## Rules

Always show the observation next to the suggestion — "`aws` appears in 434
commands" is what makes `deploy-on-aws` a recommendation rather than an
advertisement. A suggestion with no observation behind it should not be offered.

If the finding is absent, say there was no confident match — and say *why*.
Running `lookback explore` without `--json` prints the reasoning behind a zero:
which commands this scope is made of, which were left out as too widespread to
describe anything, and which the cached catalogue simply has no entry for. "Your
signature here is `cargo`, and the catalogue has nothing for that ecosystem" is a
real answer; silence is not.

Padding the list with weak matches is the other failure, and the worse one. A
term with no catalogue entry means there is nothing to suggest, not that
something nearby will do.
