#!/usr/bin/env bash
# vi_star_indices_ready: both host and plus STAR Genome files must exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

vi_star_indices_ready "$tmp" && {
  echo "test_vi_star_indices_ready: empty tree must not be ready" >&2
  exit 1
}

mkdir -p "${tmp}/host_star/star" "${tmp}/plus_star/star"
: >"${tmp}/host_star/star/Genome"
vi_star_indices_ready "$tmp" && {
  echo "test_vi_star_indices_ready: plus Genome missing" >&2
  exit 1
}

: >"${tmp}/plus_star/star/Genome"
vi_star_indices_ready "$tmp" || {
  echo "test_vi_star_indices_ready: both Genome files should be ready" >&2
  exit 1
}

echo "test_vi_star_indices_ready: ok"