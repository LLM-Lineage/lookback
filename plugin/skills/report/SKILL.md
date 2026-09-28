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

**Never apply a change yourself.** The report is evidence, not authorization.
Answer follow-up questions against the counts and the source records, and hand
over the text for the user to paste. Do not edit `settings.json`, `CLAUDE.md` or
`AGENTS.md` off a finding.

**Quote the evidence.** Every finding carries counts for a reason: the user
should be able to disagree with it. A recommendation they cannot check is one
they should not take.

**Do not inflate.** If `findings` is empty, say so. Reaching for something to
recommend is how a report becomes noise.

**The data is the user's own conversations.** Summarise what a finding is about;
do not quote prompt samples back at length, and do not copy them anywhere.
