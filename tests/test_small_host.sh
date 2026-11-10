#!/usr/bin/env bash
# small_host: gate VI on prebuilt ref/vi_star and print HPC offload instructions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

fixture="${ROOT}/config/.test_small_host_site.yaml"
trap 'rm -f "$fixture"' EXIT
yq '.small_host = true' "${ROOT}/config/local.vi-only.config.yaml" >"$fixture"

load_config "$fixture"
[[ "$(cfg '.small_host')" == "true" ]] || {
  echo "test_small_host: small_host not true in merged config" >&2
  exit 1
}

stderr="$(mktemp)"
trap 'rm -f "$fixture" "$stderr"' EXIT
set +e
"${ROOT}/bin/check.sh" "$fixture" >"$stderr" 2>&1
rc=$?
set -e

[[ "$rc" -eq 2 ]] || {
  echo "test_small_host: expected check.sh exit 2 (got ${rc})" >&2
  cat "$stderr" >&2
  exit 1
}
grep -q 'small_host is enabled' "$stderr" || {
  echo "test_small_host: missing small_host notice" >&2
  cat "$stderr" >&2
  exit 1
}
grep -q 'hpc_build_vi_star_indices.sh' "$stderr" || {
  echo "test_small_host: missing HPC script name in notice" >&2
  cat "$stderr" >&2
  exit 1
}
grep -q 'STAR_GENOMEGENERATE' "$stderr" || {
  echo "test_small_host: missing STAR_GENOMEGENERATE explanation" >&2
  cat "$stderr" >&2
  exit 1
}

load_config "${ROOT}/config/local.config.yaml"
[[ "$(cfg '.small_host // false')" == "false" ]] || {
  echo "test_small_host: local.config.yaml should default small_host false" >&2
  exit 1
}

echo "test_small_host: ok"
