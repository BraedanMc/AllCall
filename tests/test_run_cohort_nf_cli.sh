#!/usr/bin/env bash
# Cohort launcher must pass params with -c (not -params-file) and wire VI viral_fasta.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/run_cohort.sh"

grep -q '\-c "\$params"' "$script" || {
  echo "test_run_cohort_nf_cli: run_cohort.sh must use -c for params file" >&2
  exit 1
}

if grep -q '\-params-file' "$script"; then
  echo "test_run_cohort_nf_cli: run_cohort.sh must not use -params-file (Nextflow 26 regression)" >&2
  exit 1
fi

grep -q 'viral_fasta = ' "$script" || {
  echo "test_run_cohort_nf_cli: viralintegration params must set viral_fasta" >&2
  exit 1
}

grep -q '\-resume' "$script" || {
  echo "test_run_cohort_nf_cli: cohort runs must pass -resume" >&2
  exit 1
}

grep -q 'nf_nextflow_config_args' "$script" || {
  echo "test_run_cohort_nf_cli: nf_cmd must include site nextflow_configs" >&2
  exit 1
}

echo "test_run_cohort_nf_cli: ok"
