#!/usr/bin/env bash
# Cohort launcher Nextflow CLI: -c params, -resume, no -params-file (NF 26 breakage).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RC="${ROOT}/bin/run_cohort.sh"

grep -q -- '-c "\$params"' "$RC" || {
  echo "test_run_cohort_nf_cli: nf_cmd must pass cohort params with -c" >&2
  exit 1
}
grep -q -- '-resume' "$RC" || {
  echo "test_run_cohort_nf_cli: nf_cmd must use -resume" >&2
  exit 1
}
if grep -q 'params-file' "$RC"; then
  echo "test_run_cohort_nf_cli: must not use -params-file (see docs/bug-reports/2026-10-23-nextflow-26-viralintegration.md)" >&2
  exit 1
fi
grep -q 'viral_fasta' "$RC" || {
  echo "test_run_cohort_nf_cli: VI params must set viral_fasta" >&2
  exit 1
}
grep -q 'snp_ready\[\$sample\]=1' "$RC" || {
  echo "test_run_cohort_nf_cli: missing snp_ready assignment" >&2
  exit 1
}
grep -q 'cds_filter"\]:-}" == succeeded' "$RC" || {
  echo "test_run_cohort_nf_cli: SNP queue must require cds_filter succeeded" >&2
  exit 1
}

echo "test_run_cohort_nf_cli: ok"
