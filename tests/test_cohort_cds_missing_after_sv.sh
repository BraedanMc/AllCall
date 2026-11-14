#!/usr/bin/env bash
# After Sarek SV succeeds, every cohort sample must reach a terminal cds_filter status.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/run_cohort.sh"

grep -q 'no CDS filter result after Sarek SV succeeded' "$script" || {
  echo "test_cohort_cds_missing_after_sv: run_cohort must fail when cds_filter stays not_started" >&2
  exit 1
}

grep -q 'allow_idle=0' "$script" || {
  echo "test_cohort_cds_missing_after_sv: run_cohort must not idle-exit while cds_filter pending" >&2
  exit 1
}

echo "test_cohort_cds_missing_after_sv: ok"