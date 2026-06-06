#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

choice=$(tuin_choose "Apple" "Banana" "Cherry" "Date" "Elderberry")
echo "You picked: $choice"
