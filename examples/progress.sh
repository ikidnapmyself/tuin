#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

tuin_section "Long-running task"
tuin_spin "Sleeping 3 seconds" -- sleep 3
echo "Done"
