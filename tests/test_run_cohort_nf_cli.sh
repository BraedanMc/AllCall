#!/usr/bin/env bash
# Cohort Nextflow CLI: -c params (NF 24.x), viralintegration viral_fasta, no -params-file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/bin/run_cohort.sh"

grep -q '\-params-file' "$SCRIPT" && {
  echo "test_run_cohort_nf_cli: run_cohort must not use -params-file (NF 26 breakage)" >&2
  exit 1
}

grep -q '\-c "\$params"' "$SCRIPT" || {
  echo "test_run_cohort_nf_cli: nf_cmd must pass cohort params with -c" >&2
  exit 1
}

grep -q 'viral_fasta' "$SCRIPT" || {
  echo "test_run_cohort_nf_cli: viralintegration params must set viral_fasta" >&2
  exit 1
}

grep -q '\-resume' "$SCRIPT" || {
  echo "test_run_cohort_nf_cli: expected -resume on cohort runs" >&2
  exit 1
}

echo "test_run_cohort_nf_cli: ok"
