#!/usr/bin/env bash
# setup.sh --skip-kraken and Mac VI-only local config.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
setup="${ROOT}/bin/setup.sh"

grep -q -- '--skip-kraken' "$setup" || {
  echo "test_setup_skip_kraken: missing --skip-kraken flag" >&2
  exit 1
}
grep -q 'SKIP_KRAKEN' "$setup" || {
  echo "test_setup_skip_kraken: missing SKIP_KRAKEN handling" >&2
  exit 1
}
grep -qE 'SKIP_KRAKEN.*-eq 0' "$setup" || {
  echo "test_setup_skip_kraken: kraken_build should be conditional on SKIP_KRAKEN" >&2
  exit 1
}

# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"
load_config "${ROOT}/config/local.vi-only.config.yaml"

[[ "$(cfg '.species')" == "human" ]] || exit 1
[[ "$(cfg '.container_profile')" == "docker" ]] || exit 1
[[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]] || exit 1
[[ "$(cfg '.pipelines.sarek.enabled')" == "false" ]] || exit 1
[[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "false" ]] || exit 1
[[ "$(cfg '.samplesheet')" == "samplesheets/cohort.csv" ]] || exit 1

echo "test_setup_skip_kraken: ok"
