#!/usr/bin/env bash
# vi_star_indices_ready: layout used by small_host_check before VI on Mac-class hosts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

vi_star_indices_ready "$tmp" && {
  echo "test_vi_star_indices_ready: empty dir should not be ready" >&2
  exit 1
}

mkdir -p "${tmp}/host_star/star" "${tmp}/plus_star/star"
: >"${tmp}/host_star/star/Genome"
vi_star_indices_ready "$tmp" && {
  echo "test_vi_star_indices_ready: missing plus Genome should not be ready" >&2
  exit 1
}

: >"${tmp}/plus_star/star/Genome"
vi_star_indices_ready "$tmp" || {
  echo "test_vi_star_indices_ready: both Genome files should be ready" >&2
  exit 1
}

echo "test_vi_star_indices_ready: ok"
