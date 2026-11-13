#!/usr/bin/env bash
# vi_star_indices_ready: both host and plus STAR Genome files required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
vi_root="${tmp}/ref/vi_star"

vi_star_indices_ready "$vi_root" && {
  echo "test_vi_star_indices_ready: empty tree should not be ready" >&2
  exit 1
}

mkdir -p "${vi_root}/host_star/star" "${vi_root}/plus_star/star"
: >"${vi_root}/host_star/star/Genome"
vi_star_indices_ready "$vi_root" && {
  echo "test_vi_star_indices_ready: missing plus Genome should not be ready" >&2
  exit 1
}

: >"${vi_root}/plus_star/star/Genome"
vi_star_indices_ready "$vi_root" || {
  echo "test_vi_star_indices_ready: both Genome files should be ready" >&2
  exit 1
}

echo "test_vi_star_indices_ready: ok"
