---
name: postmortem
description: Read the moments in this repository's transcripts where something actually went wrong - a command that failed then worked, a search that found nothing, a file rewritten nine times - and turn them into CLAUDE.md lines. Use when the user asks why sessions here keep struggling, what Claude keeps getting wrong, wants a deeper look than the counted findings give, or says /lookback:postmortem.
---

# Reading what went wrong

Every other Lookback finding counts. This one reads.

Counting answers "which commands fail" completely — a rule, pasted, done. It
cannot answer *why* a command failed thirty times, what the model assumed that
was wrong, or which sentence would have prevented the whole detour. That is in
the transcript and nowhere else.

The transcripts are about a gigabyte, so the rule is simple: **you never read the
corpus, you read what the selector hands you.**

```sh
lookback episodes --repo . --budget 25000 --json
```

## What comes back

Candidates, ranked, already excerpted and already inside the budget:

- `kind` — `recovery` (failed, then worked), `thrash` (searched, wrote nothing),
  `churn` (one file rewritten over and over)
- `reason` — why it was selected, with the count behind it
- `records` — the turns themselves, condensed to `[assistant] …`, `[Bash] …`,
  `[result error] …`; long ones keep their head and tail with the middle marked
- `spent_tokens` / `budget_tokens` / `not_read`

**Check `not_read` before concluding anything is absent.** Above zero means
candidates were selected and did not fit, not that there was nothing more.

## Procedure

1. Run the command. Scope to a repository unless asked otherwise — a postmortem
   about "everything on this machine" produces advice with nowhere to put it.

2. **Read the excerpts.** For each, work out three things:
   - what the model believed that was not true;
   - what turned out to be true;
   - the sentence that would have saved the detour.

   The third is the deliverable. The first two are how you get there.

3. **Group before proposing.** Four episodes that all come down to "the test
   command is not what it looks like" are one line in `CLAUDE.md`, not four.
   A repeated mistake is the one worth writing down; a one-off usually is not.

4. **Hand over the text, with its evidence.** Every proposal carries the episode
   it came from and the excerpt that shows it. This is not optional here — see
   the rules below.

## Going deeper

The default reads everything in one pass, which is cheapest in tokens and spends
your context. When the user wants a thorough pass, fan out instead:

```sh
lookback episodes --repo . --budget 60000 --out-dir .lookback-episodes
```

That writes one self-contained JSON file per episode and prints the paths. Then
**dispatch one agent per file**, each told to read its own file and return only:
the wrong belief, the true fact, and the proposed line. You collect the
judgements, group them, and never load an excerpt yourself.

The trade is explicit: one call per episode instead of one call total, in
exchange for a context that stays nearly empty and excerpts that get read
properly rather than skimmed. Use it when the user asks for depth; do not
default to it.

Delete the directory when finished.

## Rules

**Label these differently, because they are different.** Counted findings carry
`basis: measured` and can be checked — the reader can run the query and disagree
with the number. A reading cannot. Anything produced here is
`basis: inferred`, and must say so in the words you use: "reading the
transcript, it looks like…" not "your sessions show…".

**Never propose a line without the excerpt behind it.** A counted finding earns
trust by being checkable. A read one earns it by being quotable. Strip either
away and the first wrong suggestion costs the credibility of every right one.

**Say when an episode is inconclusive.** Plenty of them are: the excerpt is
truncated, the reason is ambiguous, or the model simply got unlucky. "Three of
these seven say something; the rest do not" is a good report. Manufacturing
seven findings from seven episodes is how this becomes noise.

**Do not write files.** Propose the `CLAUDE.md` text; the user applies it. The
one exception in all of Lookback is `lookback install`, and this is not it.

**The excerpts are the user's own conversations.** Quote the line that proves the
point, not the surrounding paragraphs, and copy nothing anywhere else.
