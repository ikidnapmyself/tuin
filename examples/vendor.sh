#!/usr/bin/env bash
#
# vendor.sh — fetch a pinned tuin.sh and verify its SHA-256 before installing.
#
# Safe vendoring: pin a release VERSION and that release's published DIGEST,
# verify the download, fail closed on mismatch. Source this file to get
# vendor_tuin, or run it directly to vendor once. Zero deps beyond curl +
# shasum (or sha256sum). bash 3.2-safe.
#
# Pin these to the release you trust (digest comes from the release notes;
# every value here is a placeholder — set all three before you rely on it):
TUIN_VERSION="${TUIN_VERSION:-vX.Y.Z}"
TUIN_SHA256="${TUIN_SHA256:-REPLACE_WITH_PUBLISHED_DIGEST}"
TUIN_URL="${TUIN_URL:-}"
# Default resolves next to vendor.sh; callers normally override TUIN_LOCAL to
# their vendor destination (e.g. deps/tuin/tuin.sh).
TUIN_LOCAL="${TUIN_LOCAL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tuin.sh}"

# _vendor_sha256 <file> — print the file's SHA-256 (lowercase hex only).
# Named with a _vendor_ prefix so it never collides with tuin's _tuin_ helpers
# when vendor.sh is sourced alongside tuin.sh. Zero extra deps.
_vendor_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}' | tr 'A-F' 'a-f'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}' | tr 'A-F' 'a-f'
    else
        echo "vendor: need shasum or sha256sum to verify tuin" >&2
        return 1
    fi
}

# vendor_tuin — fetch -> verify -> atomically install. Fail closed.
vendor_tuin() {
    command -v curl >/dev/null 2>&1 || { echo "vendor: curl is required" >&2; return 1; }
    [ -n "$TUIN_URL" ] || { echo "vendor: set TUIN_URL to the release tuin.sh URL" >&2; return 1; }

    local dir tmp got
    # Stage the download in the destination directory so the final install is a
    # same-filesystem rename (atomic). A missing/unwritable dir fails here,
    # before any fetch — still fail closed, nothing partial ever lands.
    dir="$(dirname "$TUIN_LOCAL")"
    tmp="$(mktemp "$dir/.tuin.XXXXXX" 2>/dev/null)" || {
        echo "vendor: cannot stage download in $dir (missing or unwritable?)" >&2
        return 1
    }

    if ! curl -fsSL "$TUIN_URL" -o "$tmp"; then
        echo "vendor: fetch failed ($TUIN_URL)" >&2
        rm -f "$tmp"; return 1
    fi

    got="$(_vendor_sha256 "$tmp")" || { rm -f "$tmp"; return 1; }
    local want; want="$(printf '%s' "$TUIN_SHA256" | tr 'A-F' 'a-f')"
    if [ "$got" != "$want" ]; then
        echo "vendor: checksum mismatch — expected $TUIN_SHA256, got $got" >&2
        echo "vendor: refusing to install unverified bytes (fail closed)" >&2
        rm -f "$tmp"; return 1
    fi

    if ! mv "$tmp" "$TUIN_LOCAL"; then
        echo "vendor: install failed ($TUIN_LOCAL)" >&2
        rm -f "$tmp"; return 1
    fi
    echo "vendor: tuin $TUIN_VERSION verified -> $TUIN_LOCAL" >&2
}

# Run directly (not when sourced) -> vendor once.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    vendor_tuin
fi
