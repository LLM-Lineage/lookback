#!/usr/bin/env sh
# Lookback installer and updater. Idempotent: re-run it to update.
#
#   curl -fsSL https://raw.githubusercontent.com/LLM-Lineage/lookback-dist/main/install.sh | sh
#
# Everything is user-level. No sudo, nothing under /usr/local, nothing an IT
# policy objects to. Re-running installs the newest release over the old one
# and leaves the collected store alone.
#
# Maintained here, in the source repository, and copied into the distribution
# repository by the release. An installer that verifies a binary should be
# reviewed alongside the binary it verifies.

set -eu

REPO="LLM-Lineage/lookback-dist"
MARKET="LLM-Lineage/lookback-dist"
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
  sha256() { echo ""; }
  warn "no sha256 tool found; downloads cannot be verified"
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required to read the release manifest"

# GH_TOKEN is honoured while the distribution repository is private; unset once
# it is public. Assets are fetched through the API asset endpoint rather than
# the browser URL, because a private repository answers 404 to a browser-URL
# fetch even with a bearer token.
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
  || die "cannot reach ${REPO} releases — a private repository needs GH_TOKEN with read access"

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

# --- 3. download and verify both hashes --------------------------------------
tmp="$(mktemp -d)"
trap 'rm -r -f "${tmp}"' EXIT
say "downloading"
api_download "${asset_url}" "${tmp}/${archive}"
[ -n "${sums_url}" ] && api_download "${sums_url}" "${tmp}/checksums.json"

hash_from() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("binaries", {}).get(sys.argv[2], {}).get(sys.argv[3], ""))
PY
}

if [ -f "${tmp}/checksums.json" ]; then
  want="$(hash_from "${tmp}/checksums.json" "${target}" archive_sha256)"
  got="$(sha256 "${tmp}/${archive}")"
  [ -z "${want}" ] || [ -z "${got}" ] || [ "${want}" = "${got}" ] || die "archive checksum mismatch"
  say "archive verified"
fi

say "unpacking"
tar -xzf "${tmp}/${archive}" -C "${tmp}"
extracted="$(find "${tmp}" -name lookback -type f | head -1)"
[ -n "${extracted}" ] || die "no lookback binary in the archive"

# The authoritative check: it covers the file that actually executes, rather
# than trusting the unpack step.
if [ -f "${tmp}/checksums.json" ]; then
  want="$(hash_from "${tmp}/checksums.json" "${target}" binary_sha256)"
  got="$(sha256 "${extracted}")"
  [ -z "${want}" ] || [ -z "${got}" ] || [ "${want}" = "${got}" ] || die "binary checksum mismatch"
  say "binary verified"
fi

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
if command -v claude >/dev/null 2>&1; then
  say "installing the plugin"
  claude plugin marketplace add "${MARKET}" 2>/dev/null \
    || claude plugin marketplace update "${MARKETPLACE_NAME}" 2>/dev/null || true
  # Anchored: a substring match also matched `lookback@lineage-llm-src`, the
  # local development install, so this took the update path for a plugin that
  # was not there.
  if claude plugin list 2>/dev/null | grep -qE "(^|[^-[:alnum:]])${PLUGIN}([^-[:alnum:]]|$)"; then
    claude plugin update "${PLUGIN}" 2>/dev/null || true
  else
    claude plugin install "${PLUGIN}" 2>/dev/null \
      || warn "run: claude plugin install ${PLUGIN}"
  fi
else
  warn "claude not found; then: claude plugin marketplace add ${MARKET} && claude plugin install ${PLUGIN}"
fi

# --- 7. first collection -----------------------------------------------------
# Lookback says nothing until it has read the transcripts, and reading them is
# the slowest thing it does. Doing it now means the first question a user asks
# is answered immediately rather than after a minute of silence.
say "reading what Claude Code has already written"
"${BIN}" collect || warn "run \`lookback collect\` yourself; nothing else is needed"
say "done. Try \`lookback review\`, or /lookback:review inside Claude Code."
