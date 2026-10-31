#!/usr/bin/env bash
# kraken_ready: database marker files (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
db="${tmp}/kraken2"

kraken_ready "$db" && {
  echo "test_kraken_ready: empty dir should not be ready" >&2
  exit 1
}

mkdir -p "$db"
: >"${db}/hash.k2d"
kraken_ready "$db" && {
  echo "test_kraken_ready: missing opts.k2d should not be ready" >&2
  exit 1
}

: >"${db}/opts.k2d"
kraken_ready "$db" || {
  echo "test_kraken_ready: hash.k2d + opts.k2d should be ready" >&2
  exit 1
}

echo "test_kraken_ready: ok"
