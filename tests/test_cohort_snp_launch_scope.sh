#!/usr/bin/env bash
# SNP completion must not mark samples that became cds-ready after the Sarek SNP run launched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/run_cohort.sh"

grep -q 'snp_launched_samples=.*ready' "$script" || {
  echo "test_cohort_snp_launch_scope: run_cohort must snapshot SNP cohort at launch" >&2
  exit 1
}

grep -q 'for s in "\${snp_launched_samples\[@\]}"; do STATUS\["\${s}|sarek_snp"\]' "$script" || {
  echo "test_cohort_snp_launch_scope: SNP completion must only update launched samples" >&2
  exit 1
}

if grep -q 'for s in "\${!snp_ready\[@\]}"; do STATUS\["\${s}|sarek_snp"\]' "$script"; then
  echo "test_cohort_snp_launch_scope: must not mark every snp_ready sample on SNP exit" >&2
  exit 1
fi

echo "test_cohort_snp_launch_scope: ok"
