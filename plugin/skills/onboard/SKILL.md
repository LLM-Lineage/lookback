---
name: onboard
description: Set a repository up for Claude Code - draft its CLAUDE.md from what sessions here actually ran, propose the skills and commands worth writing, and move the configuration only you have into something the whole team gets. Use when the user asks how to onboard a repo, set up Claude for a project, write a CLAUDE.md, or says /lookback:onboard.
---

# Onboarding a repository

```sh
lookback onboard --target . --json
```

Every other Lookback mode asks what *this user* should change. This one asks
what the repository fails to tell anyone who opens it — so the fix is committed
and helps the next person, not just the one running the command.

## What comes back

`onboarding.project` is what the repository has on disk: the names at its root,
its memory files, its `.claude/` assets, its CI workflows. There is no table of
stacks behind it. The root listing is the evidence, and reading `mix.exs` or
`BUILD.bazel` and knowing what it means is your job, not the collector's.

`onboarding.devloop` is the valuable part: the commands sessions have actually
run here, most-used first, each with the shortest working invocation, how often
it failed, and whether the repository's memory already mentions it. This is
derived from transcripts, so it is what people do rather than what the README
claims.

`findings` are the ordinary repository-scoped findings plus the onboarding ones:
`no-project-memory`, `undocumented-devloop`, `unshared-configuration`,
`no-repository-skills`.

## Procedure

1. Run the command above.

2. **Read the repository before drafting anything.** The devloop says *what*
   runs; only the repository says why. Open the root files the listing named, the
   CI workflows, and the existing `CLAUDE.md` if there is one. A `CLAUDE.md` that
   contradicts the build config is worse than none.

3. **Draft, showing the evidence beside each line.** For a repository with no
   memory file, propose the whole thing. For one that has it, propose only the
   additions — `documented: false` is what to look at.

4. **Check the devloop against CI.** A command that runs constantly in sessions
   but never in CI is often a local habit rather than the project's real gate,
   and the workflow file is the more authoritative statement. Where they
   disagree, say so rather than picking one silently.

5. **Hand over the draft first.** Apply only a specific edit the user explicitly
   requests, after inspecting the target and showing the diff and scope.

6. **Offer to make the repository carry Lookback**, once — this is the moment for
   it, and nothing else in the flow raises it:

   ```sh
   lookback install            # prints the change
   lookback install --write    # applies it
   ```

   It merges `enabledPlugins` and `extraKnownMarketplaces` into the repository's
   `.claude/settings.json`, so whoever clones it gets `/lookback:review` without
   being told Lookback exists. Say two things when you offer it:

   - it is a change to a file the team shares, so it wants reviewing and
     committing like any other;
   - **it carries the plugin, not the binary.** A settings file cannot hold an
     executable, so a teammate who has never run the installer gets the commands
     and `lookback: command not found` from them. They each run the one-liner once.

   Offer it; do not run `--write` unless the user asks for it.

## What makes a good CLAUDE.md here

The devloop gives you the commands. What makes the file worth reading is the
part that cannot be derived:

- **The gates.** What has to pass before a change is proposed, in the order it
  runs. Take this from CI where CI exists.
- **What is easy to get wrong.** `relearned-each-session` in the findings is
  exactly this: things sessions worked out, used, and lost. Each one is a fact
  that currently lives only in a transcript.
- **The workflow rules** — branch naming, whether `main` is protected, commit
  conventions — which a session cannot infer and will otherwise guess.
- **What the repository is for.** One paragraph. A session that knows the
  purpose makes better calls than one that has only read the file tree.

Leave out anything a session can read for itself. A list of directories that
restates the tree is context spent on nothing.

## Skills and commands

`no-repository-skills` fires when a repository has none. The candidates are
procedures rather than preferences: several commands in a fixed order, run more
than once — releasing, migrating, regenerating fixtures, cutting a report.

A skill's `description` decides whether it is ever reached for, so write it in
the words someone would actually use to ask, not in the words the skill uses
about itself.

## Rules

**Never apply a change yourself.** Hand over the text; let the user paste it.
Do not create or edit `CLAUDE.md`, `.claude/settings.json`, `AGENTS.md` or a
skill off a finding, even when asked to — say what to paste and where. The one
exception in all of Lookback is `lookback install --write`, the CLI's own
separate plugin-install operation, and this is not it.

**Say where each suggestion came from.** Every finding carries a `basis`:
`measured` was drawn from this machine, `structural` follows from what Claude
Code records, and `default` means there is not yet enough history here to
measure and a shipped baseline was used. A `default` suggestion is a starting
point and should be offered as one.

**Do not invent a devloop.** If `onboarding.devloop` is empty, the repository has
no recorded history and the honest answer is that there is nothing to draft from
yet — read the CI config and say that is what you are working from.

**The data is the user's own work.** Summarise; do not quote transcripts at
length or copy them anywhere.
