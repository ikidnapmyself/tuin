#!/usr/bin/env bats

# Compute a fixture's SHA-256 with whichever tool exists, mirroring the
# shasum-or-sha256sum fallback in examples/vendor.sh, so these tests run on
# systems that ship only one of the two.
_fixture_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

setup() {
    load 'test_helper/common-setup'
    _common_setup
    VENDOR_SH="$TUIN_REPO_ROOT/examples/vendor.sh"
    SRC="$BATS_TEST_TMPDIR/source.sh"
    DEST="$BATS_TEST_TMPDIR/tuin.sh"
    printf 'echo hi\n' > "$SRC"
}

@test "vendor_tuin installs a file whose digest matches the pin" {
    local sum
    sum="$(_fixture_sha256 "$SRC")"
    run env TUIN_URL="file://$SRC" TUIN_SHA256="$sum" TUIN_LOCAL="$DEST" \
        bash -c "source '$VENDOR_SH'; vendor_tuin"
    assert_success
    [ -f "$DEST" ]
    assert_equal "$(cat "$DEST")" "$(cat "$SRC")"
}

@test "vendor_tuin fails closed and writes nothing on digest mismatch" {
    run env TUIN_URL="file://$SRC" TUIN_SHA256="deadbeef" TUIN_LOCAL="$DEST" \
        bash -c "source '$VENDOR_SH'; vendor_tuin"
    assert_failure
    [ ! -f "$DEST" ]
    assert_output --partial "checksum mismatch"
}

@test "vendor_tuin accepts an uppercase pinned digest" {
    local sum
    sum="$(_fixture_sha256 "$SRC" | tr 'a-f' 'A-F')"
    run env TUIN_URL="file://$SRC" TUIN_SHA256="$sum" TUIN_LOCAL="$DEST" \
        bash -c "source '$VENDOR_SH'; vendor_tuin"
    assert_success
    [ -f "$DEST" ]
}

@test "vendor_tuin fails closed when the destination dir is missing" {
    local sum
    sum="$(_fixture_sha256 "$SRC")"
    run env TUIN_URL="file://$SRC" TUIN_SHA256="$sum" \
        TUIN_LOCAL="$BATS_TEST_TMPDIR/nope/tuin.sh" \
        bash -c "source '$VENDOR_SH'; vendor_tuin"
    assert_failure
    [ ! -f "$BATS_TEST_TMPDIR/nope/tuin.sh" ]
    assert_output --partial "cannot stage download"
}