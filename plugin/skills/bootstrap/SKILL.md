---
name: bootstrap
description: Start a new repository from a spec, matching how this machine's existing repositories are already set up - clarify the spec, ask what production will need, and scaffold in the house style rather than a generic template. Use when the user wants to start a new project, bootstrap a repo, set up a new service or library, or says /lookback:bootstrap.
---

# Starting a new repository

```sh
lookback bootstrap --list-orgs --json      # which organization is this for?
lookback bootstrap --org <name> --json     # read it, plus this machine
lookback bootstrap --json                  # this machine only, no network
```

The point of doing this here rather than from a template is that the user
already has repositories, and they already answer most of the questions a
template would ask. A new one that matches them is a new one where everything
they know still applies.

## Which organization

**Ask, unless the spec already answers it.** A person can belong to a dozen
organizations, and each has its own conventions; picking the wrong one produces
a confident, wrong house style and nothing in the output will look unusual.

`--list-orgs` returns the choices and marks the one this directory's `origin`
remote points at. Take the answer from the spec where it is there — a named
team, a sibling repository, an existing service this one talks to — and ask
outright where it is not. One question, early, before anything is proposed.

Then run with `--org <name>`. Its repositories outrank this machine's: a new
repository joins a team, not a laptop. Where the two disagree, the organization
wins and the local count is context.

`--org` is the only part of Lookback that uses the network. It reads through the
user's own `gh` CLI and sends nothing from the local store. If `gh` is missing
or the user would rather not, drop the flag — everything still works from this
machine alone, on a smaller sample.

## What comes back

Counts, not advice. Nothing in the output is interpreted, because interpreting
it is this skill's job:

- `common_artifacts` — files and directories the existing repositories carry,
  with how many carry each, split into `in_org` and `local`. `settled: true`
  means enough of them agree to call it the house style — judged against the
  organization whenever one was read. This is the whole convention set, whatever it happens to
  contain: `.github/` or `.gitlab-ci.yml`, `Makefile` or `justfile` or `mix.exs`,
  and the ones nobody would ever put in a template — a `.specs/` directory, an
  in-house marker file, a vendored toolchain pin.
- `task_runners` — what each repository reaches for most, one vote per
  repository.
- `shared_rules` — permission rules more than one repository decided on.
- `claude` — how many carry a memory file, their own settings, their own skills.
- `examined` — how many repositories all of the above was read from.

## Procedure

1. **Get the spec.** A file, or the user's description. If it is a file, read it.

2. **Run it,** with `--org` once the organization is settled, and read the
   artifact list properly. An
   unfamiliar name is the most valuable thing in it: a directory in nine of
   someone's fourteen repositories is a convention they will expect and will not
   think to mention. Look inside one or two of the `repositories` listed to see
   what such a directory actually contains before proposing it.

3. **Ask what the spec does not say.** Derive the questions from the gap between
   the spec and the artifact list rather than from a checklist. If most of their
   repositories carry something that implies a production concern — deployment
   config, an environment example file, infrastructure definitions, a changelog,
   a security policy — ask how this project answers it. If their repositories
   carry nothing of the sort, that is worth one question, not a lecture.

   Ask the questions that change what gets built, together, in one pass. Do not
   interrogate one at a time.

4. **Propose the layout,** naming for each part whether it came from their
   repositories (and how many), from the spec, or from you. The third kind needs
   to be visibly the third kind.

5. **Confirm before writing anything.** Then create the files, in an empty or
   new directory only. Never scaffold over an existing repository — that is
   `/lookback:onboard`, which proposes and does not write.

6. **Finish with the devloop.** The repository should be able to build, test and
   run before the conversation ends, and `CLAUDE.md` should say how in the words
   the commands actually take.

## Judgement this skill has to supply

The command counts; it does not know what anything means. Reading `terraform/`,
`charts/`, `docker-compose.yml`, `.env.example`, `renovate.json` and knowing what
each implies about how this team ships is yours to do.

Two things worth holding onto:

**A convention carried by most of their repositories is not optional.** If
eleven of fourteen have a memory file and this one will not, say so and ask.

**Prefer the organization's count to the machine's.** `4 of 6 in the org, 2 of
14 here` is a team convention that this machine happens to have few examples of
— it is stronger evidence than the local number makes it look, not weaker.

**Something carried by some of them is a decision, not a default.** Present it as
a choice with the count attached: "six of your fourteen have a Makefile" is a
question. Deciding it silently is how a scaffolder starts producing repositories
nobody wants.

## Where the estate is silent

With fewer than three repositories there is no house style to inherit, and the
command says so. Do not fill the gap by asserting one — say that this is the
first repository the tooling has seen, ask the questions the spec leaves open,
and make the decisions explicitly with the user so that the *next* repository
has something to inherit from.

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


**Confirm before creating files, and only into an empty directory.** Bootstrap is
the one mode that writes, because the alternative is dictating a file tree into
a chat window. It still asks first, and it never writes over work that exists.

**Attribute every choice.** "Nine of your repositories do this" and "I am
suggesting this" are different claims and must read differently.

**Do not invent a house style.** The output is counts from real repositories. If
something is not in it, it is not their convention, and proposing it is fine only
when it is labelled as your suggestion.

**The data is the user's own work.** Summarise; do not copy file contents around.
