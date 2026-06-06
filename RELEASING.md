# Releasing tuin

tuin ships as a single file. A release is a git tag **plus a published SHA-256
digest**, so anyone vendoring tuin can pin and verify it (see "Vendoring tuin
safely" in the README).

## Checklist

1. Move `## [Unreleased]` in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD`.
2. Bump `_TUIN_VERSION` and the `# Version:` header in `tuin.sh`.
3. Compute the digest: `make checksum`
4. Record that digest in the new CHANGELOG entry **and** in the release notes,
   in the exact form `make checksum` prints: `<64-hex sha256>  tuin.sh`
5. `git tag -a vX.Y.Z -m 'tuin vX.Y.Z'`
6. `git push origin main --tags`
7. Publish the release with the digest line from step 4 in its body.

## Why publish the digest

Adopters verify their vendored `tuin.sh` against a pinned SHA-256. That pin is
only trustworthy if it comes from the release — a hash computed from the same
download proves nothing. Publishing it in the release notes and CHANGELOG gives
adopters a value to pin that is independent of their own fetch.
