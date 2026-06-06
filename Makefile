.PHONY: test lint checksum release clean help

BATS := tests/test_helper/bats-core/bin/bats

help:
	@echo "Targets:"
	@echo "  test     Run BATS test suite"
	@echo "  lint     Run shellcheck over tuin.sh and examples"
	@echo "  checksum Print the SHA-256 of tuin.sh (publish this with each release)"
	@echo "  release  Print release checklist (no automation yet)"
	@echo "  clean    Remove BATS run artifacts"

test:
	$(BATS) tests/

lint:
	shellcheck tuin.sh examples/*.sh tests/test_helper/common-setup.bash

checksum:
	@if command -v shasum >/dev/null 2>&1; then shasum -a 256 tuin.sh; \
	elif command -v sha256sum >/dev/null 2>&1; then sha256sum tuin.sh; \
	else echo "need shasum or sha256sum" >&2; exit 1; fi

release:
	@echo "Release checklist:"
	@echo "  1. Update CHANGELOG.md (move Unreleased -> new version)"
	@echo "  2. Bump tuin_version inside tuin.sh"
	@echo "  3. Run 'make checksum' and record the digest in CHANGELOG + release notes"
	@echo "     (see RELEASING.md)"
	@echo "  4. git tag -a vX.Y.Z -m 'tuin vX.Y.Z'"
	@echo "  5. git push origin main --tags"

clean:
	find tests -name '*.log' -delete 2>/dev/null || true
