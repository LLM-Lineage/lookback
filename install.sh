#!/usr/bin/env sh
# Lookback installer and updater. Idempotent: re-run it to update.
#
#   curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback/main/install.sh | sh
#
# Everything is user-level. No sudo, nothing under /usr/local, nothing an IT
# policy objects to. Re-running installs the newest release over the old one
# and leaves the collected store alone.
#
# Maintained here, in the source repository, and copied into the distribution
# repository by the release. An installer that verifies a binary should be
# reviewed alongside the binary it verifies.

set -eu

REPO="LLM-Lineage/lookback"
MARKET="LLM-Lineage/lookback"
# `lineage-llm` is already bavarde's marketplace. Claude Code keys marketplaces
# by name, so reusing it meant `marketplace add` failed on the collision, the
# fallback silently updated *bavarde's* marketplace instead, and the install
# reported success having installed nothing.
MARKETPLACE_NAME="lookback"
PLUGIN="lookback@lookback"
STATE="${HOME}/.lookback"
BIN_DIR="${STATE}/bin"
BIN="${BIN_DIR}/lookback"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$1" >&2; exit 1; }

# --- 0. uninstall ------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  say "removing the binary and PATH shim"
  rm -f "${BIN}" "${HOME}/.local/bin/lookback"
  if command -v claude >/dev/null 2>&1; then
    claude plugin uninstall "${PLUGIN}" 2>/dev/null || true
    claude plugin marketplace remove "${MARKETPLACE_NAME}" 2>/dev/null || true
  fi
  if [ "${2:-}" = "--purge" ]; then
    # The store is derived from ~/.claude and can always be rebuilt, but it is
    # the user's own history and is not removed without being asked.
    warn "purging ${STATE} — the collected store"
    rm -r -f "${STATE}"
  else
    say "the store at ${STATE} is kept; pass --uninstall --purge to remove it too"
  fi
  say "done"
  exit 0
fi

# --- 1. platform -------------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "${os}:${arch}" in
  Darwin:arm64)              target="aarch64-apple-darwin" ;;
  Darwin:x86_64)             target="x86_64-apple-darwin" ;;
  Linux:x86_64)              target="x86_64-unknown-linux-musl" ;;
  Linux:aarch64|Linux:arm64) target="aarch64-unknown-linux-gnu" ;;
  *) die "no build for ${os} on ${arch}" ;;
esac

# One question, two tools: macOS ships `shasum`, Linux ships `sha256sum`.
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  # No third branch. This script downloads an executable and runs it; without a
  # way to check what arrived, the only safe thing it can do is stop.
  die "no sha256 tool found (need sha256sum or shasum); cannot verify the download"
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required to read the release manifest"

# Where Claude Code keeps its own state. It honours CLAUDE_CONFIG_DIR, so this
# does too - otherwise a sandboxed run would read the real configuration.
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

# What Claude Code has cached as this marketplace's source, empty when it has no
# entry. Read from its own file rather than scraped out of `marketplace list`,
# whose output is written for people and is free to change.
marketplace_repo() {
  python3 - "${CLAUDE_HOME}/plugins/known_marketplaces.json" "${MARKETPLACE_NAME}" <<'MKT'
import json, sys
# One guard around the decode *and* the traversal. Structurally valid JSON of an
# unexpected shape — a null where an object belongs, a list at the top level —
# raises just as readily as a syntax error, and an uncaught raise here exits 1.
# The caller assigns this in a command substitution under `set -e`, so that
# would end the install rather than fall through to "nothing cached".
try:
    document = json.load(open(sys.argv[1]))
    entry = document.get(sys.argv[2]) or {}
    print((entry.get("source") or {}).get("repo", ""))
except Exception:
    sys.exit(0)
MKT
}

# Where OMP keeps its own marketplace registry, which is a different file in a
# different directory from Claude Code's and has the same stale-name problem.
#
# Resolved the way omp 18.3.5 was *observed* to resolve it, by planting a
# marketplace with the real binary under a sandboxed HOME and finding which
# `marketplaces.json` it wrote (2026-10-02, re-measured 2026-10-03):
#
#   neither                           ->  ${HOME}/.omp
#   PI_CONFIG_DIR=custom-omp          ->  ${HOME}/custom-omp
#   PI_PROFILE=work                   ->  ${HOME}/.omp/profiles/work
#   PI_CONFIG_DIR + PI_PROFILE        ->  ${HOME}/custom-omp/profiles/work
#   XDG_DATA_HOME with omp/ present   ->  ${XDG_DATA_HOME}/omp
#   the same, plus PI_CONFIG_DIR      ->  ${XDG_DATA_HOME}/omp   (PI_CONFIG_DIR
#                                                                 is ignored)
#   the same, plus PI_PROFILE=work    ->  ${HOME}/.omp/profiles/work  (XDG is
#                                                                      ignored)
#
# Three things that are easy to get wrong, each one measured rather than
# reasoned about:
#
#  1. **The XDG rule is real, and it is conditional on the directory existing.**
#     An earlier pass here recorded the opposite, from an experiment that
#     created ${XDG_DATA_HOME} but not ${XDG_DATA_HOME}/omp — so the condition
#     was false, omp fell back to ${HOME}/.omp, and that was written down as
#     "omp does not follow XDG". With ${XDG_DATA_HOME}/omp present omp puts
#     `marketplaces.json` there, which on a machine that has one made this
#     function read a registry omp never writes and report no stale marketplace
#     whatever was actually registered.
#
#     `logs/` is the trap: it stays in the *config* directory even when the
#     registry moves to the XDG data directory, so watching where the logs land
#     measures the wrong thing. The only reliable probe is where
#     `marketplaces.json` itself is written.
#
#  2. **The XDG branch only applies when no profile is selected**, and it beats
#     PI_CONFIG_DIR when it does apply.
#
#  3. **OMP_PROFILE wins over PI_PROFILE by being *set*, not by being
#     non-empty.** `OMP_PROFILE= PI_PROFILE=frompi` resolves to the base
#     directory, not to profiles/frompi. Profile values are trimmed, and the
#     literal `default` means the base directory rather than profiles/default.
#
# PI_CONFIG_DIR is a directory *name* joined under home, not a path — omp joins
# it itself, so passing an absolute path there does not do what it looks like.
#
# `OMP_CONFIG_DIR`, which this line used to read, is the one name that really is
# invented: the string occurs nowhere in the omp binary and setting it changes
# nothing. No fallback is kept for it, and release.test.sh greps for exactly
# that.
omp_registry() {
  # By presence, not by emptiness — see (3) above.
  if [ -n "${OMP_PROFILE+set}" ]; then
    omp_profile="${OMP_PROFILE}"
  else
    omp_profile="${PI_PROFILE:-}"
  fi
  omp_profile="$(printf '%s' "${omp_profile}" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ "${omp_profile}" = "default" ] && omp_profile=""

  # The data directory, and only without a profile — see (2).
  if [ -z "${omp_profile}" ] \
     && [ -n "${XDG_DATA_HOME:-}" ] \
     && [ -d "${XDG_DATA_HOME}/omp" ]; then
    printf '%s/omp/marketplaces.json\n' "${XDG_DATA_HOME}"
  elif [ -n "${omp_profile}" ]; then
    printf '%s/%s/profiles/%s/marketplaces.json\n' \
      "${HOME}" "${PI_CONFIG_DIR:-.omp}" "${omp_profile}"
  else
    printf '%s/%s/marketplaces.json\n' "${HOME}" "${PI_CONFIG_DIR:-.omp}"
  fi
}

# What OMP has cached as this marketplace's source, empty when it has no entry.
omp_marketplace_repo() {
  python3 - "$(omp_registry)" "${MARKETPLACE_NAME}" <<'OMPMKT'
import json, sys
# Guarded through the traversal, like the reader above and like the PowerShell
# side: `{"marketplaces": null}` makes the loop raise, not the decode.
try:
    document = json.load(open(sys.argv[1]))
    for entry in document.get("marketplaces", []):
        if entry.get("name") == sys.argv[2]:
            print(entry.get("sourceUri", ""))
            break
except Exception:
    sys.exit(0)
OMPMKT
}

# What OMP currently has installed, for telling an update from a no-op.
#
# The listing is passed as an argument, never piped. This was
# `omp plugin list --json | python3 - "${PLUGIN}" <<'OMPVER'`, and a
# here-document *is* stdin: it overrode the pipe, so `json.load(sys.stdin)`
# parsed the Python program's own text, failed, and the function printed
# nothing on every run since it was written. The installer therefore never once
# reported the OMP plugin's version or a change. shellcheck names it SC2259,
# which is why release.test.sh now gates on `shellcheck -S error`.
omp_installed_version() {
  python3 - "${PLUGIN}" "$(omp plugin list --json 2>/dev/null)" <<'OMPVER'
import json, sys
# The decode was guarded and the traversal was not, which made this *worse* than
# the version it replaced: the old reader was broken and returned empty, while
# this one raised on `{"marketplace": null}`, on a top-level list, and on an
# entry whose `entries` is null. `omp_before="$(omp_installed_version)"` under
# `set -e` turns that raise into a dead installer, so a listing from a different
# omp version would stop the install instead of reaching the warning below.
try:
    document = json.loads(sys.argv[2])
    for plugin in document.get("marketplace", []):
        if plugin.get("id") == sys.argv[1]:
            for entry in plugin.get("entries", []):
                print(entry.get("version", ""))
                sys.exit(0)
except Exception:
    sys.exit(0)
OMPVER
}

# The version Claude Code currently has, for telling an update from a no-op.
# `claude plugin update` says "Checking for updates…" either way, which is how
# somebody ends up with a new binary, old commands, and nothing saying so.
installed_version() {
  claude plugin list 2>/dev/null \
    | awk -v p="${PLUGIN}" '$0 ~ p {found=1; next} found && /Version:/ {print $2; exit}'
}

# The distribution repository is public, so no token is needed and none is asked
# for. `GH_TOKEN` is still honoured if it happens to be set — for a private fork,
# or a rate-limited network — but the documented path uses neither.
#
# Assets go through the API asset endpoint rather than the browser URL. That was
# required while the repository was private, where a browser-URL fetch answers
# 404 even with a bearer token; it is kept because it works either way and is one
# code path instead of two.
AUTH_H=""
[ -n "${GH_TOKEN:-}" ] && AUTH_H="Authorization: Bearer ${GH_TOKEN}"

api_get() {
  accept="${2:-application/vnd.github+json}"
  if [ -n "${AUTH_H}" ]; then
    curl -fsSL -H "${AUTH_H}" -H "Accept: ${accept}" "$1"
  else
    curl -fsSL -H "Accept: ${accept}" "$1"
  fi
}
api_download() {
  if [ -n "${AUTH_H}" ]; then
    curl -fsSL -H "${AUTH_H}" -H "Accept: application/octet-stream" -o "$2" "$1"
  else
    curl -fsSL -H "Accept: application/octet-stream" -o "$2" "$1"
  fi
}

# --- 2. resolve the latest release -------------------------------------------
say "finding the latest release"
release_json="$(api_get "https://api.github.com/repos/${REPO}/releases/latest")" \
  || die "cannot reach ${REPO} releases — check the network; the repository is public and needs no token"

version="$(printf '%s' "${release_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))')"
[ -n "${version}" ] || die "no release found"
say "installing ${version} for ${target}"

archive="lookback-${version#v}-${target}.tar.gz"

# A release's asset list is real JSON, not a line to sed.
asset_of() {
  printf '%s' "${release_json}" | python3 -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(a.get("url", "")); break
' "$1"
}
asset_url="$(asset_of "${archive}")"
sums_url="$(asset_of checksums.json)"
[ -n "${asset_url}" ] || die "no ${archive} in ${version}"
# A release with no manifest cannot be verified, and an unverifiable release is
# not one to install. Previously this skipped the whole check block silently —
# no warning, no mismatch, straight to running the binary.
[ -n "${sums_url}" ] || die "no checksums.json in ${version}; refusing to install unverified"

# --- 3. download and verify both hashes --------------------------------------
tmp="$(mktemp -d)"
trap 'rm -r -f "${tmp}"' EXIT
say "downloading"
api_download "${asset_url}" "${tmp}/${archive}"
api_download "${sums_url}" "${tmp}/checksums.json" \
  || die "could not download checksums.json; refusing to install unverified"

hash_from() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("binaries", {}).get(sys.argv[2], {}).get(sys.argv[3], ""))
PY
}

# Every way of not knowing is a failure, not a pass.
#
# This used to read `[ -z "$want" ] || [ -z "$got" ] || [ "$want" = "$got" ] ||
# die`, where an empty hash on either side short-circuits the whole chain to
# true — so a missing manifest entry, or a missing hash tool, skipped the
# comparison and then printed "verified" on the next line regardless. The only
# case that ever failed was the one where both hashes were present and differed.
verify() {
  _file="$1"; _field="$2"; _label="$3"
  _want="$(hash_from "${tmp}/checksums.json" "${target}" "${_field}")"
  [ -n "${_want}" ] || die "checksums.json has no ${_field} for ${target}; refusing to install"
  _got="$(sha256 "${_file}")"
  [ -n "${_got}" ] || die "could not hash ${_file}; refusing to install unverified"
  [ "${_want}" = "${_got}" ] || die "${_label} checksum mismatch (expected ${_want}, got ${_got})"
  say "${_label} verified"
}

verify "${tmp}/${archive}" archive_sha256 archive

say "unpacking"
tar -xzf "${tmp}/${archive}" -C "${tmp}"
extracted="$(find "${tmp}" -name lookback -type f | head -1)"
[ -n "${extracted}" ] || die "no lookback binary in the archive"

# The authoritative check: it covers the file that actually executes, rather
# than trusting the unpack step.
verify "${extracted}" binary_sha256 binary

# --- 4. place the binary -----------------------------------------------------
# Overwriting a signed binary in place invalidates its signature, and macOS then
# kills it on exec with a bare "killed". Remove first, for a fresh inode.
mkdir -p "${BIN_DIR}"
rm -f "${BIN}"
cp "${extracted}" "${BIN}"
chmod +x "${BIN}"
if [ "${os}" = "Darwin" ]; then
  codesign --force -s - "${BIN}" >/dev/null 2>&1 \
    || warn "could not re-sign; the binary may be killed on first run"
fi
say "installed ${BIN}"

# --- 5. PATH -----------------------------------------------------------------
mkdir -p "${HOME}/.local/bin"
ln -sf "${BIN}" "${HOME}/.local/bin/lookback"
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) : ;;
  *)
    profile="${HOME}/.zshrc"; [ -n "${BASH_VERSION:-}" ] && profile="${HOME}/.bashrc"
    # shellcheck disable=SC2016  # the literal $HOME is what belongs in a profile
    line='export PATH="$HOME/.local/bin:$PATH"'
    grep -qsF "${line}" "${profile}" 2>/dev/null \
      || printf '\n# lookback\n%s\n' "${line}" >> "${profile}"
    warn "added ~/.local/bin to PATH in ${profile}; open a new terminal to pick it up"
    ;;
esac

# --- 6. plugin ---------------------------------------------------------------
# Re-running this script is the update path, so refresh the marketplace and
# update an already-installed plugin: `install` alone is idempotent and would
# leave an old version in place.
plugin_changed=no
if command -v claude >/dev/null 2>&1; then
  say "installing the plugin"

  # An install made before the distribution repository was renamed still has the
  # old name cached. Nothing looks wrong: `marketplace add` fails on the name
  # collision, the fallback `update` re-clones from whatever was stored, and the
  # whole thing keeps working - but only because GitHub redirects the old name.
  # That redirect is a dependency nobody chose, and it stops the moment anything
  # else claims the old name, so re-point the marketplace at the real one.
  #
  # Removing a marketplace uninstalls the plugins that came from it, which is why
  # this runs *before* the block below: that block then finds no plugin and puts
  # it back. Nothing of the user's is lost either way - Lookback's state is the
  # store under ~/.lookback, not plugin data.
  stored_repo="$(marketplace_repo)"
  if [ -n "${stored_repo}" ] && [ "${stored_repo}" != "${MARKET}" ]; then
    warn "the marketplace points at ${stored_repo}; re-pointing it at ${MARKET}"
    claude plugin marketplace remove "${MARKETPLACE_NAME}" >/dev/null 2>&1 || true
  fi

  claude plugin marketplace add "${MARKET}" 2>/dev/null \
    || claude plugin marketplace update "${MARKETPLACE_NAME}" 2>/dev/null || true

  # Let Claude Code keep the plugin current by itself. `autoUpdate` is a
  # per-marketplace flag in `extraKnownMarketplaces`, and `marketplace add` does
  # not set it — so every install so far has been one somebody had to remember to
  # update. This is the host's own mechanism rather than anything of ours: the
  # setting is Claude Code's, it updates on Claude Code's schedule, and removing
  # the line turns it off.
  python3 - "${CLAUDE_HOME}/settings.json" "${MARKETPLACE_NAME}" <<'AUTOUP'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
try:
    document = json.loads(path.read_text())
except Exception:
    # No settings file, or one this script should not be rewriting blind.
    sys.exit(0)

marketplaces = document.get("extraKnownMarketplaces")
entry = marketplaces.get(sys.argv[2]) if isinstance(marketplaces, dict) else None
if not isinstance(entry, dict) or entry.get("autoUpdate") is True:
    sys.exit(0)

entry["autoUpdate"] = True
# Written back with the same indentation Claude Code uses, and with every other
# key untouched and in its original order.
path.write_text(json.dumps(document, indent=2) + "\n")
print("enabled")
AUTOUP
  if [ -n "$(python3 -c "import json,sys;d=json.load(open('${CLAUDE_HOME}/settings.json'));m=d.get('extraKnownMarketplaces',{}).get('${MARKETPLACE_NAME}',{});print('y' if m.get('autoUpdate') else '')" 2>/dev/null)" ]; then
    say "Claude Code will keep the plugin up to date by itself"
  fi
  # Anchored: a substring match also matched `lookback@lineage-llm-src`, the
  # local development install, so this took the update path for a plugin that
  # was not there.
  if claude plugin list 2>/dev/null | grep -qE "(^|[^-[:alnum:]])${PLUGIN}([^-[:alnum:]]|$)"; then
    before="$(installed_version)"
    claude plugin update "${PLUGIN}" 2>/dev/null || true
    [ "$(installed_version)" = "${before}" ] || plugin_changed=yes
  else
    if claude plugin install "${PLUGIN}" 2>/dev/null; then
      plugin_changed=yes
    else
      warn "run: claude plugin install ${PLUGIN}"
    fi
  fi
else
  warn "claude not found; then: claude plugin marketplace add ${MARKET} && claude plugin install ${PLUGIN}"
fi

# --- 6b. the OMP plugin ------------------------------------------------------
# This block did not exist, and that is why OMP drifted. The installer updated
# Claude Code's plugin every run and left OMP's wherever it was first put: six
# releases behind on the machine that found it, with `lookback review --source
# omp` reading a 0.6.1 plugin against a 0.7.3 store and nothing saying so.
#
# `install --force` rather than `upgrade`. `omp plugin upgrade` reports "All
# marketplace plugins are up to date" with 0.6.1 installed and 0.7.3 in its own
# freshly-refreshed cache, so it cannot be relied on to notice. A forced install
# from the marketplace is the operation that actually lands the current version.
if command -v omp >/dev/null 2>&1; then
  say "installing the OMP plugin"

  # The same rename repair as above. OMP stores its registry in
  # ~/.omp/marketplaces.json, so the Claude-side fix never touched it and every
  # OMP install is still pointing at the old name through a redirect.
  omp_stored="$(omp_marketplace_repo)"
  if [ -n "${omp_stored}" ] && [ "${omp_stored}" != "${MARKET}" ]; then
    warn "OMP's marketplace points at ${omp_stored}; re-pointing it at ${MARKET}"
    omp plugin marketplace remove "${MARKETPLACE_NAME}" >/dev/null 2>&1 || true
  fi

  # Whether the marketplace was actually refreshed, which is what makes a
  # later "already current" a claim about the published release rather than a
  # claim about omp's cache. `add` failing is the ordinary path — the name is
  # already registered — so `update` is the one that has to succeed then.
  omp_refreshed=yes
  if ! omp plugin marketplace add "${MARKET}" >/dev/null 2>&1 \
     && ! omp plugin marketplace update "${MARKETPLACE_NAME}" >/dev/null 2>&1; then
    omp_refreshed=no
    warn "could not refresh OMP's marketplace; the install below can only use what it has cached"
  fi

  # Always report the outcome. The symptom users saw was silence, not a wrong
  # number: the old `if` printed only on a change, and omp_installed_version
  # could never return one, so there was no path to any message at all.
  omp_before="$(omp_installed_version)"
  if omp plugin install "${PLUGIN}" --force >/dev/null 2>&1; then
    omp_after="$(omp_installed_version)"
    if [ -z "${omp_after}" ]; then
      warn "OMP installed ${PLUGIN} but reported no version for it"
    elif [ "${omp_after}" != "${omp_before}" ]; then
      say "OMP plugin ${omp_before:-none} -> ${omp_after}"
    elif [ "${omp_refreshed}" = yes ]; then
      say "OMP plugin ${omp_after}, already current"
    else
      # Equality proves *unchanged*, not *current*. With both marketplace
      # operations failed, a forced install can still succeed from cached files
      # and leave the version where it was — which is how an install reported
      # "already current" while sitting releases behind the marketplace it
      # could not reach.
      warn "OMP plugin ${omp_after} unchanged, and its marketplace could not be refreshed, so whether that is the current release is unknown"
    fi
  else
    warn "run: omp plugin install ${PLUGIN} --force"
  fi
fi

# --- 7. first collection -----------------------------------------------------
# Lookback says nothing until it has read the transcripts, and reading them is
# the slowest thing it does. Doing it now means the first question a user asks
# is answered immediately rather than after a minute of silence.
say "reading what Claude Code has already written"
"${BIN}" collect || warn "run \`lookback collect\` yourself; nothing else is needed"

# Claude Code registers a plugin's skills when a session starts. Updating the
# plugin under a session that is already open leaves it with the previous
# version's commands and nothing to say so — which reads as the new command
# simply not existing.
if [ "${plugin_changed}" = yes ]; then
  say "done. The binary is ready now; \`lookback review\` works in this terminal."
  warn "the plugin changed — restart Claude Code to pick up its commands"
else
  say "done. Try \`lookback review\`, or /lookback:review inside Claude Code."
fi
