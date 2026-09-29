# Lookback

**Your Claude Code sessions already know what your configuration is missing.**

Every session leaves a transcript, and those transcripts record which skill,
which subagent and which plugin drove each tool call, what each turn cost, and
which calls failed. Nobody reads them.

Lookback reads them, compares what you actually do against what you have
actually configured, and hands you the change to make: the permission rule to
add, the instruction you have retyped in nine sessions that belongs in
`CLAUDE.md`, the skill nobody invokes, the devloop a repository never wrote down.

**Everything stays on your machine.** There are no network calls in collection or
in reporting — including the plugin suggestions, which match against the
catalogue Claude Code has already cached. The single exception is opt-in and
named: `lookback bootstrap --org <name>` reads your organization's repository
listing through your own `gh` CLI, and sends nothing from the local store.

**Lookback proposes; you apply.** Nothing it reports edits your
`settings.json`, `CLAUDE.md` or `AGENTS.md` — not the CLI, and not the agent
reading its findings. You are handed the exact text to paste. The two exceptions
are commands you run on purpose: `lookback install --write`, which adds the
plugin to a repository, and `lookback bootstrap`, which writes a new
repository's scaffolding after asking.

---

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback/main/install.sh | sh
```

### What the installer does

1. Verifies the SHA-256 of the archive **and** of the binary inside it. If
   anything cannot be verified — no manifest, no entry for your platform, no
   hash tool on the machine — it stops rather than installing.
2. Puts the binary in `~/.lookback/bin` and links it into `~/.local/bin`,
   adding that to your `PATH` if it is not already there.
3. Adds `lookback` as a Claude Code marketplace and installs the plugin.
4. Runs the first collection, so the first question you ask is answered
   immediately rather than after a minute of silence.

Platforms: macOS (Apple Silicon and Intel) and Linux (x86-64 and arm64).
Requires `python3`, `curl`, and `sha256sum` or `shasum`.

**Windows is not shipped yet.** There is a Windows build and a PowerShell
installer, and both work as far as they can be checked without Windows — but
nothing has yet run the test suite there, and the differences that matter on
Windows are the quiet kind: a report that covers the whole machine when you asked
about one repository. Rather than ship that and let you find out, it waits for a
green test run on Windows. If you want it sooner, say so — knowing somebody is
waiting is the thing most likely to move it.

### Updating

**Re-running the installer is the update path.** It replaces the binary, updates
the plugin, and leaves your collected store alone.

```sh
curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback/main/install.sh | sh
```

Check what you have with `lookback --version`, and what Claude Code has with
`claude plugin list`. They should match; if the plugin is behind, **restart
Claude Code** — it registers a plugin's commands when a session starts, so an
update applied under an open session leaves it with the previous version's
commands and nothing saying so.

Using OMP as well? Update its copy of the plugin too, in OMP's REPL:

```
/marketplace update lookback
/marketplace install lookback@lookback
```

The first refreshes the marketplace; the second reinstalls the plugin from it,
qualified — see the warning under **Inside OMP** about the bare name. Then
`omp plugin list` should show `lookback@lookback (<version>) (user)`. Restart
OMP afterwards, for the same reason as Claude Code: extensions load at start.

An out-of-date binary is detected rather than guessed at: the OMP tool will tell
you it predates multi-source reporting instead of returning a shape its own
description contradicts.

### Removing

```sh
install.sh --uninstall           # remove the binary and the plugin, keep the store
install.sh --uninstall --purge   # remove the collected store as well
omp plugin uninstall lookback-omp   # the OMP plugin, if you installed it
```

The store is your own collected history and is kept unless you ask for it to go;
it is a derived cache and rebuilds from your transcripts in about ten seconds.

---

## First five minutes

```sh
lookback review          # everything, ending with what to improve
```

That collects and reports in one pass. From inside a repository, scope it:

```sh
cd ~/code/your-project
lookback review --repo   # only this repository's sessions
```

Or use Claude Code directly:

```
/lookback:review
```

Ask follow-up questions in the same session. Challenge a finding by asking for
its counts or source; ask for a specific recommendation to be applied if you
agree. The agent should show the target and diff before editing; a finding is
not itself permission to change configuration.

### Inside OMP

The installer above supplies the verified `lookback` executable. Install the
same released plugin from OMP's marketplace — in OMP's REPL:

```
/marketplace add LLM-Lineage/lookback
/marketplace install lookback@lookback
```

or from a shell:

```sh
omp plugin marketplace add LLM-Lineage/lookback
omp plugin install lookback@lookback
```

> **Always the qualified `lookback@lookback`, never a bare `lookback`.**
> The name after the `@` is the marketplace. Without it, `omp plugin install
> lookback` resolves the name against the public npm registry instead, where a
> package called `lookback` already exists and belongs to someone else. It
> installs without complaint, and OMP runs plugin code — so the mistake is
> quiet and it executes. Anything you install from us is
> `<plugin>@<marketplace>`.

Uninstalling needs `bun` on your `PATH` (`brew install bun`); OMP uses it to
manage the plugin directory. Without it an uninstall fails partway and leaves
OMP's lock file claiming a plugin that is no longer there, which then blocks the
next install with a conflict against itself.

Restart OMP to load its extension, then enter `/lookback` to review this
machine's Claude Code and OMP sessions. `/lookback <question>` starts from a
specific question, and you can keep challenging the evidence in the conversation
that follows — the counts are there to be disagreed with. As everywhere else, it
proposes and you apply.

OMP clones the marketplace over Git, which needs nothing special now that the
distribution repository is public.

OMP collection reads `~/.omp/agent/sessions/**/*.jsonl` (override the agent
directory with `LOOKBACK_OMP_HOME`) into `~/.lookback/omp.sqlite`, separately
from Claude Code's `~/.lookback/store.sqlite`. It records redacted prompt and
command excerpts, tool outcomes and token usage. OMP does not record Claude's
skill attribution or settings: OMP reports therefore omit permission, plugin
and effort recommendations. The currently supported OMP findings are failed
commands, repeated prompts and commands relearned across sessions, plus cost
totals. Review evidence before asking for an edit; project instructions belong
in `AGENTS.md` or `.omp/AGENTS.md`, not Claude permission rules.

---

## Every command

By default `collect` reads every session source present — `~/.claude` and
`~/.omp/agent` — each into its own local store, skipping any that is absent;
`review` collects and reports in one pass, one report per source. Collection is
incremental. With every source selected, `--json` prints
`{"reports": [...], "skipped": [...]}`, each report tagged with its `source`.
`--source claude` or `--source omp` reads one alone and prints a bare report.
OMP supports `review`, `collect`, `report`, `rules`, `context`, `cost` and
`episodes`. The rest need Claude Code's own configuration, which an OMP
transcript does not carry: `explore` matches against Claude Code's plugin
catalogue, `install` writes a Claude Code plugin, `effort` reads a per-turn
field OMP does not record, and `onboard` and `bootstrap` describe a repository
in terms of Claude Code's setup.

| Command | What it answers |
|---|---|
| `lookback review` | Everything, ending with what to improve. Collects first. |
| `lookback collect` | Read `~/.claude` and `~/.omp/agent` into their local stores. Nothing is printed but counts. |
| `lookback report` | Everything the store has to say about your setup. |
| `lookback rules` | Permission rules and `CLAUDE.md` entries worth adding. |
| `lookback effort` | Model and reasoning-effort settings that do not match the work. |
| `lookback context` | What this repository should tell every session before it starts. |
| `lookback cost` | Where the tokens went, by skill, subagent and tool. |
| `lookback explore` | Plugins worth trying, matched offline against the cached catalogue. |
| `lookback onboard` | What a repository should tell the next person who opens it. |
| `lookback bootstrap` | How your repositories are set up, for starting a new one. |
| `lookback episodes` | The moments in your transcripts worth reading, and only those. |
| `lookback install` | Enable Lookback for a repository, so it arrives with the clone. |

### Common options

| Option | Meaning |
|---|---|
| `--global` | Every repository on this machine, rather than just this one. |
| `--repo <path>` | A repository other than the one you are in. |
| `--source <all\|claude\|omp>` | Which session history to read; default `all`. Each source keeps its own store. |
| `--json` | Machine-readable output, which is what the skills read. |
| `--min-calls <n>` | Ignore anything rarer than this. |
| `--store <path>` | Use a different store. Also `LOOKBACK_STORE`. Names one store, so it needs `--source claude` or `--source omp`. |
| `--claude-home <path>` | Read a different `~/.claude`. Also `LOOKBACK_CLAUDE_HOME`. |
| `--omp-home <path>` | Read another OMP agent directory. Also `LOOKBACK_OMP_HOME`. |

**The repository you are in is the default.** That is almost always the
question, and a machine-wide answer buries it in work from every other project.
`--global` asks the wider one.

Two cases widen on their own and say so: running outside a repository, and
running in one with no recorded sessions. The second prints
`No sessions recorded for …, so this covers the whole machine` before the
report — an empty repository is not a finding that its setup is fine.

Work done in a **git worktree** is folded back into the repository it was cut
from, so per-task checkouts do not look like separate projects. Inside Claude
Code the repository is resolved from `$CLAUDE_PROJECT_DIR`, which is what lets
the plugin report on wherever you are without being told.

### Setting up a repository

```sh
lookback onboard --target .         # what this repository fails to tell people
lookback context --repo             # what every session here should be told first
```

`onboard` reports the repository's real devloop — the commands sessions actually
run here, the shortest working form of each, and whether the repository's own
`CLAUDE.md` mentions them — alongside what is missing: the memory file, the
skills nobody wrote, the configuration only you have.

### Starting a new repository

```sh
lookback bootstrap                  # what your repositories have in common
lookback bootstrap --list-orgs      # which organization is this for?
lookback bootstrap --org <name>     # read it too; it outranks this machine
```

There is no template behind this and no checklist. A convention is whatever
recurs, so it finds the `.specs/` directory nobody would have put in a list as
readily as the `.github/` directory everybody would.

`--org` is the one command that touches the network. It goes through your own
`gh` CLI and sends nothing from the store.

### Applying the permission rules

```sh
lookback rules                    # print them
lookback rules --write            # apply them to this repository
lookback rules --write --global   # apply them to ~/.claude/settings.json
```

The same careful merge `install` uses: everything already in the file is kept,
including key order. It **only ever adds** to `permissions.allow` and never
touches `deny` or `ask`. When git does not track the file, a copy is written
beside it first and the path is printed.

If a blanket `Bash` is already allowing everything, the additions change nothing
until it goes — and removing it takes authority away, so it needs its own word:

```sh
lookback rules --write --narrow   # also remove the blanket the rules replace
```

Every command the new rules do not name will start asking again after that. It
is the point of the change, and worth knowing before you make it.

### Remembering an instruction

```sh
lookback remember --text "After a task, commit and push without being asked."
lookback remember --write --text "..."            # actually add it
lookback remember --write --global --text "..."   # to ~/.claude/CLAUDE.md
lookback remember --write --agents --text "..."   # to OMP's AGENTS.md
```

Appends one line to the memory file every session reads, under a heading of its
own. It **never composes or edits** — it places the text you give it — and it
never rewrites or removes anything already there. A duplicate word for word is
refused. Without `--write` it prints what it would do and stops.

This exists so an instruction you have read and agreed to does not need an agent
editing your `CLAUDE.md` by hand to get there. Deciding the words is still
yours; placing them is not.

### Giving a repository Lookback of its own

```sh
lookback install --target /path/to/repo           # print the change
lookback install --target /path/to/repo --write   # apply it
```

Merges `enabledPlugins` and `extraKnownMarketplaces` into that repository's
`.claude/settings.json`, leaving everything else — including key order — alone.
Everyone who clones it then gets Lookback without being told to install it.

### Reading what went wrong

Findings count; episodes read. A command that failed then worked, a session that
searched without writing, a file rewritten nine times — *why* those happened is
in the transcript and nowhere else.

```sh
lookback episodes --repo . --budget 25000            # selected, excerpted, budgeted
lookback episodes --repo . --kind recovery           # one kind: recovery, thrash, churn
lookback episodes --repo . --out-dir ./episodes      # one file each, to read in parallel
```

The transcripts are about a gigabyte, so nothing reads them whole. The selector
picks a few dozen turns and everything stays inside the token budget you set.
`--out-dir` writes one self-contained file per episode, which is what lets a
Claude Code session hand each to a separate agent and keep its own context empty.

---

## Inside Claude Code

Nine commands, installed with the plugin. **Restart Claude Code after installing
or updating** — it registers a plugin's commands when a session starts.

| Command | What it does |
|---|---|
| `/lookback:review` | **Start here.** Finds the issues, reports them, proposes the fixes. |
| `/lookback:repo` | What this repository should be telling every session. |
| `/lookback:rules` | Permission rules and `CLAUDE.md` entries worth adding. |
| `/lookback:report` | The findings alone, without the collect step. |
| `/lookback:onboard` | Set this repository up for the people who open it. |
| `/lookback:bootstrap` | Start a new repository in your own house style. |
| `/lookback:explore` | Plugins worth trying, matched offline. |

`/lookback:review` is the one to reach for. It does three passes in order: the
counted findings, where the tokens actually went, and — when the counts have not
explained something — a read of the moments in your transcripts where something
went wrong. That last pass is the only part that can say *why* a command kept
failing, rather than how often.

---

## Reading a finding

Every finding carries the evidence it was drawn from — counts, sessions, the
window it covers — and says where it came from:

| Basis | Meaning |
|---|---|
| **measured** | Counted on your machine. You can run the query and disagree. |
| **structural** | Follows from what Claude Code records, not from a judgement. |
| **inferred** | Read out of a transcript. Plausible, not counted. |
| **default** | A shipped fallback, because there is not yet enough history. |

A recommendation that cannot say where it came from is an assertion. Nothing
Lookback suggests is a shipped opinion about what your work should look like:
the conventions it reports are derived from your own corpus, which is why it can
recognise a house style it has never seen.

---

## Verifying a download yourself

Each release carries `checksums.json` and `SHA256SUMS`. `binary_sha256` is the
authoritative one: it covers the file that actually executes, checked after
unpacking, rather than trusting the unpack step.

```sh
gh release download v<version> --repo LLM-Lineage/lookback --dir lookback
cd lookback && sha256sum -c SHA256SUMS
```

---

## If something goes wrong

**`lookback: command not found`** — the installer added `~/.local/bin` to your
`PATH` in your shell profile. Open a new terminal, or run
`export PATH="$HOME/.local/bin:$PATH"`.

**`/lookback:…` is an unknown command** — the plugin was installed or updated
under a session that was already open. Restart Claude Code.

**The installer says it cannot reach the releases** — check the network, and
that `curl` and `python3` are on your `PATH`. The repository is public, so no
token or login is needed.

**It refuses to install, saying it cannot verify** — that is deliberate. A
release with no `checksums.json`, no entry for your platform, or a machine with
no `sha256sum`/`shasum` cannot be checked, and an unverifiable binary is not one
to run. Install `coreutils` if the hash tool is what is missing.

**A report says there is not enough collected yet** — run `lookback collect`.
If you have only just started using Claude Code, some findings need a few
sessions' history before they can be measured rather than guessed.

**The store looks wrong after an update** — it is a derived cache and rebuilds
from `~/.claude` in about ten seconds. Delete `~/.lookback/store.sqlite` and run
`lookback collect`.

---

## License

MIT. See [LICENSE](LICENSE).
