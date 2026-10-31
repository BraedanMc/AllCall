#!/usr/bin/env bash
# Regression: cohort Nextflow CLI uses -c params and VI resource caps (NF 24.10.5 pin).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cohort="${ROOT}/bin/run_cohort.sh"

grep -e '-c "$params"' "$cohort" >/dev/null || {
  echo "test_run_cohort_nextflow_cli: nf_cmd must pass params via -c" >&2
  exit 1
}
if grep -q 'params-file' "$cohort"; then
  echo "test_run_cohort_nextflow_cli: must not use deprecated -params-file" >&2
  exit 1
fi
grep -qF 'viral_fasta' "$cohort" || {
  echo "test_run_cohort_nextflow_cli: viralintegration params need viral_fasta key" >&2
  exit 1
}
if grep -qF 'virus_fasta' "$cohort"; then
  echo "test_run_cohort_nextflow_cli: obsolete virus_fasta param name" >&2
  exit 1
fi
grep -qF 'max_cpus = 8' "$cohort" || {
  echo "test_run_cohort_nextflow_cli: missing VI max_cpus cap" >&2
  exit 1
}
grep -qF 'max_memory = "20.GB"' "$cohort" || {
  echo "test_run_cohort_nextflow_cli: missing VI max_memory cap" >&2
  exit 1
}

echo "test_run_cohort_nextflow_cli: ok"
