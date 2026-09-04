#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "AGENTS.md exists" {
    [ -f "$TUIN_REPO_ROOT/AGENTS.md" ]
}

@test "every public tuin_ function is documented in AGENTS.md" {
    local fn
    while IFS= read -r fn; do
        grep -qF "$fn" "$TUIN_REPO_ROOT/AGENTS.md" \
            || fail "AGENTS.md is missing public function: $fn"
    done < <(grep -oE '^tuin_[a-z_]+' "$TUIN_SH")
}

@test "CLAUDE.md imports AGENTS.md" {
    grep -qF '@AGENTS.md' "$TUIN_REPO_ROOT/CLAUDE.md"
}

@test "GEMINI.md references AGENTS.md" {
    grep -qF 'AGENTS.md' "$TUIN_REPO_ROOT/GEMINI.md"
}

@test "README documents the vendoring trust model" {
    grep -qF 'Vendoring tuin safely' "$TUIN_REPO_ROOT/README.md" \
        || fail "README.md is missing the 'Vendoring tuin safely' section"
}

@test "README vendoring section states the fail-closed digest behavior" {
    grep -qF 'checksum mismatch' "$TUIN_REPO_ROOT/README.md" \
        || fail "README.md does not mention 'checksum mismatch'"
    grep -qF 'fail closed' "$TUIN_REPO_ROOT/README.md" \
        || fail "README.md does not mention 'fail closed'"
}

@test "README points at the vendoring example" {
    grep -qF 'examples/vendor.sh' "$TUIN_REPO_ROOT/README.md" \
        || fail "README.md does not link examples/vendor.sh"
}

@test "RELEASING.md exists" {
    [ -f "$TUIN_REPO_ROOT/RELEASING.md" ]
}

@test "RELEASING.md documents publishing the digest" {
    grep -qF 'make checksum' "$TUIN_REPO_ROOT/RELEASING.md" \
        || fail "RELEASING.md does not reference 'make checksum'"
    grep -qiF 'sha-256' "$TUIN_REPO_ROOT/RELEASING.md" \
        || fail "RELEASING.md does not mention SHA-256"
}

@test "README documents every TUIN_* environment variable used in tuin.sh" {
    local var
    while IFS= read -r var; do
        grep -qF "$var" "$TUIN_REPO_ROOT/README.md" \
            || fail "README.md is missing env var: $var"
    done < <(grep -oE '\$\{TUIN_[A-Z_]+' "$TUIN_SH" | tr -d '${' | sort -u)
}

@test "README has a keyboard reference for tuin_choose" {
    grep -qF 'ctrl-n' "$TUIN_REPO_ROOT/README.md"
    grep -qF 'shift-tab' "$TUIN_REPO_ROOT/README.md"
}

@test "docs/ROADMAP.md exists" {
    [ -f "$TUIN_REPO_ROOT/docs/ROADMAP.md" ]
}

@test "tuin.sh header no longer carries the Ctrl-C known limitation" {
    ! grep -q 'Known v0.1.0 limitation' "$TUIN_SH"
}
