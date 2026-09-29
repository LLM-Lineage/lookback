---
name: report
description: Report what this machine's Claude Code history says about the user's own setup - which permission rules are missing, which skills are never invoked, which subagent is being over-used, where the tokens go. Use when the user asks how to improve their Claude Code configuration, what their usage looks like, why sessions feel slow or expensive, or says /lookback:report.
---

# Reporting on a Claude Code setup

Lookback reads transcripts, prompt history and settings that are already on this
machine, and turns them into changes the user can make. Everything is local; no
network call is involved, in collection or in reporting.

## Procedure

1. Refresh the store. It is incremental, so this is fast after the first run:

   ```sh
   lookback collect
   ```

2. Read the findings as structured data:

   ```sh
   lookback report --json
   ```

   The output covers every session source present on this machine: Claude Code
   and OMP. It is `{"reports": [...], "skipped": [...]}`. Each report carries
   `source` (`claude` or `omp`), `scope`, `totals` and `findings`; `skipped` names each source left out and
   why (nothing collected, or no sessions in scope). Present each source under its
   own heading and never merge their counts. OMP findings belong in `AGENTS.md`;
   they are never Claude Code permission rules. Pass `--source claude` or
   `--source omp` to read one alone, which returns a single bare report.

3. Present them. Lead with the finding that covers the most activity — the list
   is already ordered that way. For each, give the user the *change*, then the
   evidence that justifies it.

## What the output means

Each finding carries `improves` (`rules`, `skills`, `subagents` or `explore`),
`evidence` (the counts it was drawn from) and `actions` (what to actually do).
`totals` is orientation rather than advice: it names no change.

## Rules for reporting this
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


**Never edit their files yourself.** The report is evidence, not authorization.
Answer follow-up questions against the counts and the source records. When the
user asks for something specific to be applied, `lookback rules --write` places
permission rules and `lookback remember --write --text "..."` places one agreed
instruction — use those rather than `Edit`. A finding alone is never enough.

**Quote the evidence.** Every finding carries counts for a reason: the user
should be able to disagree with it. A recommendation they cannot check is one
they should not take.

**Do not inflate.** If `findings` is empty, say so. Reaching for something to
recommend is how a report becomes noise.

**The data is the user's own conversations.** Summarise what a finding is about;
do not quote prompt samples back at length, and do not copy them anywhere.
