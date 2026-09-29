---
name: review
description: Find what is wrong with this Claude Code setup, report it with the evidence, and propose the fixes - the counted findings, where the tokens went, and the moments in the transcripts where something actually went wrong. Use when the user asks for a review, asks what to improve, wants to know where their tokens go, wants to know why sessions here keep struggling, or says /lookback:review.
---

# Find the issues, report them, propose the fixes

```sh
lookback review --json
```

One command. It collects first (incremental, so fast after the first run), then
reports every finding ordered by how much of the user's activity each covers,
with the totals alongside.

**It covers every session source on this machine — Claude Code and OMP — and
reports on each separately.** The payload is `{"reports": [...], "skipped": [...]}`:
each report carries `source` (`claude` or `omp`), `scope`, `totals` and
`findings`, and `skipped` names every source left out and why (nothing
collected, or no sessions in scope). Present each source under its own heading
and **never merge their counts** — they are different tools with different
histories. `--source claude` or `--source omp` reads one alone and returns a
single bare report.

**An OMP finding belongs in `~/.omp/agent/AGENTS.md`, never in a Claude Code
permission rule.** OMP has no `permissions.allow`, so a rule-shaped suggestion
there is advice the user cannot apply.

**It reports on the repository the user is in.** That is the default, because it
is almost always the question. Add `--global` for every repository on the
machine.

Two cases widen automatically: not being in a repository at all, and being in
one with no recorded sessions. The second says so first —
`No sessions recorded for …, so this covers the whole machine` — and then gives
the machine-wide report. **Repeat that when you present it.** An empty
repository is not a finding that its setup is fine, and the numbers below the
notice answer a wider question than the one that was asked; a reader who misses
that reads them against the wrong scope. `scope` in the JSON is always what was
actually covered, so trust it over what the user typed.

## The three passes

Do them in this order. Each is cheaper than the next, and each one narrows what
the next has to look at.

### 1. What is wrong — the findings

`findings`, ordered by weight. Lead with the top one. For each, give the
**change** first and the evidence second. Every finding carries `improves`:

| | |
|---|---|
| `rules` | permission rules and CLAUDE.md |
| `context` | what the repository tells a session before it starts |
| `subagents` | which agent gets delegated to |
| `effort` | the model and reasoning effort left set |
| `skills` | which skills exist and how they are described |
| `explore` | plugins worth trying |

### 2. Where the effort went — the totals

`totals`, in the same payload. This is orientation, not advice: it names no
change, so do not invent one from it.

Attribution is **recorded, not estimated** — Claude Code stamps every record
with `attributionSkill`, `attributionAgent` and `attributionPlugin`, and every
assistant message with its own usage. So "this skill spent that" is a fact here,
not a guess.

`cache_read_tokens` is usually far larger than input and output and costs a
fraction. A high ratio of `cache_creation` to `cache_read` means context is
being rebuilt rather than reused — worth mentioning when it stands out. A
subagent with few calls but heavy tokens is doing expensive work per
invocation, which is a different problem from one that is merely used often.

State the window the numbers cover (`first_seen` to `last_seen`). A total with
no window is a number nobody can act on.

**Quote `active_hours`, not the span, when you say how much work this was.**
Claude Code reuses one session id across `--continue` and `--resume`, so a
"session" is a file that can cover weeks and `first_seen` to `last_seen` is
calendar time. `active_hours` sums the gaps between consecutive turns and discards
any gap over thirty minutes. On the corpus this was written against the span was
five months and the work was 210 hours; treating the span as effort overstates it
by more than ten times.

`turns_per_prompt` and `calls_per_prompt` say how much happens between one
instruction and the next. Neither is a problem in either direction — a corpus at
57 turns per prompt is being used very differently from one at three, and saying
which it is tells the reader something no finding does.

**`failed_calls`, `failures_by_command` and `interruptions` are where effort was
lost.** They are still orientation: name them, do not turn them into advice. The
`failing-command` finding is the actionable half and it fires on a different
question — a prefix failing at least half the time — so a tool called 2,000 times
and failing 300 appears here and in no finding.

`interruptions` is the one measured signal that Claude was going the wrong way:
every other number counts what was attempted, not what a person decided to stop.
Report it plainly and without apology or inference — it is a count, and the reason
behind any one of them is in the transcript, not in the total.

### 3. Why it went wrong — the episodes

Everything above counts. This one reads, and it is the only part that can say
*why* a command failed thirty times or which sentence would have prevented a
detour. Reach for it when the counted findings have not explained something, or
when the user asks why sessions here keep struggling.

```sh
lookback episodes --repo . --budget 25000 --json
```

The transcripts are about a gigabyte, so **never read the corpus — read what the
selector hands you.**

The payload is `{"readings": [...], "skipped": [...]}` — one reading per source
that had something to read, each with its own `source` (`claude` or `omp`), `scope`
and accounting, and a reason for every source left out. Present them separately and
never merge them: an OMP episode argues for a line in `AGENTS.md`, never for a
Claude Code permission rule.

`--budget` is a ceiling across all of them and it is divided by how much each
source actually holds, so a source with nothing to read takes none of it. Read
`budget_tokens` on each reading to see what it was given rather than assuming an
even split.

Each reading is already excerpted and already inside its share of the budget:

- `kind` — `recovery` (failed, then worked), `thrash` (searched, wrote nothing),
  `churn` (one file rewritten over and over)
- `reason` — why it was selected, with the count behind it
- `records` — the turns, condensed; long ones keep their head and tail
- `not_read` — **check this before concluding anything is absent.** Above zero
  means candidates were selected and did not fit, not that there was no more.
  Raising `--budget` is what reaches them; the whole increase goes to the sources
  that have something left to read.

For each excerpt, work out three things: what the model believed that was not
true, what turned out to be true, and the sentence that would have saved the
detour. The third is the deliverable; the first two are how you get there.

**Group before proposing.** Four episodes that all come down to "the test
command is not what it looks like" are one line in `CLAUDE.md`, not four.

**Label these differently, because they are different.** A counted finding
carries `basis: measured` and can be checked — the reader can run the query and
disagree. A reading cannot. Anything from this pass is `basis: inferred` and
must say so in the words used: "reading the transcript, it looks like…", not
"your sessions show…".

**Never propose a line without the excerpt behind it.** A counted finding earns
trust by being checkable; a read one earns it by being quotable. Strip either
away and the first wrong suggestion costs the credibility of every right one.

**Say when an episode is inconclusive.** Plenty are. "Three of these seven say
something; the rest do not" is a good report. Manufacturing seven findings from
seven episodes is how this becomes noise.

Going deeper, when the user asks for a thorough pass: `--out-dir` writes one
self-contained file per episode and prints the paths, each named for the source
it came from (`claude-00-recovery.json`). Dispatch one agent per
file, each returning only the wrong belief, the true fact and the proposed line.
You collect the judgements and never load an excerpt yourself. One call per
episode instead of one call total, in exchange for a context that stays nearly
empty. Do not default to it. Delete the directory afterwards.

## Rules

**Never edit their files yourself.** A finding is evidence, not an instruction:
invite challenges and re-check a disputed claim against its source. When the
user has read something and asked for it, Lookback has commands that place it —
use those rather than `Edit`:

```sh
lookback rules --write                            # the permission rules
lookback remember --write --text "<agreed line>"  # one instruction, into CLAUDE.md
```

Both print what they would do, refuse duplicates, never remove what somebody
else wrote, and copy the file first when git does not track it. Neither decides
anything: the words are still yours to propose and theirs to agree to.

**Quote the evidence.** Each finding carries counts so the user can disagree.
A recommendation they cannot check is one they should not take.

**Do not inflate.** An empty `findings` list means say so. A finding that does
not fire is information: `effort-overkill` staying silent means the effort
settings match the work, which is worth stating plainly rather than padding.

**The data is the user's own conversations.** Quote the line that proves the
point, not the surrounding paragraphs, and copy nothing anywhere else.
