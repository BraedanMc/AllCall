#!/usr/bin/env bash
# expand_user_path tilde and HOME variants (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

assert_expanded() {
  local label="$1" input="$2" want="$3"
  local got
  got="$(expand_user_path "$input")"
  if [[ "$got" != "$want" ]]; then
    echo "test_expand_user_path: ${label} want '${want}' got '${got}'" >&2
    exit 1
  fi
}

assert_expanded "bare tilde" '~' "$HOME"
assert_expanded "tilde slash" '~/scratch/allcall' "${HOME}/scratch/allcall"
assert_expanded "dollar HOME" '$HOME' "$HOME"
assert_expanded "dollar HOME slash" '$HOME/scratch' "${HOME}/scratch"
assert_expanded "dollar HOME suffix" '$HOMEVAR' "${HOME}VAR"
assert_expanded "brace HOME" '${HOME}' "$HOME"
assert_expanded "brace HOME path suffix" '${HOME}projects/allcall' "${HOME}projects/allcall"
assert_expanded "passthrough relative" 'relative/path' 'relative/path'
assert_expanded "passthrough absolute" '/var/tmp' '/var/tmp'

echo "test_expand_user_path: ok"
