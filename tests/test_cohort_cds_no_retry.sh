#!/usr/bin/env bash
# CDS filter must not retry after a failed attempt (SNP can launch while status is failed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/run_cohort.sh"

grep -qF '${STATUS["${sample}|cds_filter"]:-not_started}" != failed' "$script" || {
  echo "test_cohort_cds_no_retry: run_cohort.sh must skip CDS retry after failed" >&2
  exit 1
}

grep -q 'has CDS BAM but was not included in the Sarek SNP pass' "$script" || {
  echo "test_cohort_cds_no_retry: run_cohort.sh must detect orphaned CDS BAMs after SNP" >&2
  exit 1
}

echo "test_cohort_cds_no_retry: ok"
