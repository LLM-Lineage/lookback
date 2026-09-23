# Lookback

**Your Claude Code sessions already know what your configuration is missing.**

Every session leaves a transcript, and those transcripts record which skill,
which subagent and which plugin drove each tool call, what each turn cost, and
which calls failed. Nobody reads them.

Lookback reads them, compares what you actually do against what you have
actually configured, and hands you the change to make: the permission rule to
add, the instruction you have retyped in nine sessions that belongs in
`CLAUDE.md`, the skill nobody invokes, the devloop a repository never wrote down.

Everything stays on your machine. There are no network calls in collection or in
reporting — including the plugin suggestions, which match against the catalogue
Claude Code has already cached. The single exception is opt-in and named:
`lookback bootstrap --org <name>` reads your organization's repository listing
through your own `gh` CLI, and sends nothing from the local store.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback-dist/main/install.sh | sh
```

**While this repository is private**, a raw URL returns 404 even with a token, so
fetch the installer through the API instead. The simplest token is your own `gh`
login:

```sh
export GH_TOKEN=$(gh auth token)
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/LLM-Lineage/lookback-dist/contents/install.sh | sh
```

The installer puts the binary in `~/.lookback/bin`, links it into
`~/.local/bin`, adds this repository as a Claude Code marketplace, installs the
plugin, and reads your existing transcripts so the first question you ask is
answered immediately. It verifies the SHA-256 of both the archive and the binary
inside it before anything is placed.

Re-running it is also how you update. `install.sh --uninstall` removes
everything and keeps your collected store; add `--purge` to remove that too.

## Using it

```sh
lookback review              # everything, ending with what to improve
lookback review --repo       # scoped to the repository you are in
lookback onboard --target .  # what this repository should tell the next person
lookback bootstrap           # how your repositories are set up, for starting one
```

Or ask it inside Claude Code:

```
/lookback:review     everything, ending with what to improve
/lookback:onboard    set this repository up for the people who open it
/lookback:bootstrap  start a new repository in your own house style
/lookback:repo       what this repository should tell every session
/lookback:rules      permission rules worth adding
/lookback:cost       where the tokens went, by skill and subagent
/lookback:explore    plugins worth trying, matched offline
```

Every finding carries the evidence it was drawn from — counts, sessions, the
window it covers — and says whether it was **measured** on your machine, follows
**structurally** from what Claude Code records, or came from a shipped
**default** because there is not yet enough history to measure. A recommendation
that cannot say where it came from is an assertion.

Lookback proposes; you apply. It does not edit your `settings.json` or your
`CLAUDE.md`.

## Verifying a download

Each release carries `checksums.json` and `SHA256SUMS`. `binary_sha256` is the
authoritative one: it covers the file that actually executes, checked after
unpacking, rather than trusting the unpack step.

```sh
gh release download v<version> --repo LLM-Lineage/lookback-dist --dir lookback
sha256sum -c lookback/SHA256SUMS
```

## License

MIT. See [LICENSE](LICENSE).
