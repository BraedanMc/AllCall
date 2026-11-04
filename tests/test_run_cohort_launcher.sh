#!/usr/bin/env bash
# Regression guards for run_cohort Nextflow launcher (NF 24 / viralintegration 0.1.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cohort="${ROOT}/bin/run_cohort.sh"

if grep -q -- '-params-file' "$cohort"; then
  echo "run_cohort: must not use -params-file (breaks pinned NF 24 cohort params)" >&2
  exit 1
fi
grep -q -- '-c "$params"' "$cohort" || {
  echo "run_cohort: expected cohort params via -c" >&2
  exit 1
}
grep -q 'viral_fasta' "$cohort" || {
  echo "run_cohort: viralintegration params must use viral_fasta" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$cohort" || {
  echo "run_cohort: viralintegration max_cpus cap missing" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$cohort" || {
  echo "run_cohort: viralintegration max_memory cap missing" >&2
  exit 1
}
grep -qE '\.pipelines\.sarek\.enabled.*snp_started.*snp_ready' "$cohort" || {
  echo "run_cohort: SNP launch must gate on sarek.enabled" >&2
  exit 1
}

echo "test_run_cohort_launcher: ok"
