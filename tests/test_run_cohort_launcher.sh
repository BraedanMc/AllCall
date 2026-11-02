#!/usr/bin/env bash
# run_cohort launcher regressions (NF 24 pin, viralintegration params, params via -c).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cohort="${ROOT}/bin/run_cohort.sh"

grep -Fq 'viral_fasta =' "$cohort" || {
  echo "test_run_cohort_launcher: viralintegration must use viral_fasta param" >&2
  exit 1
}
grep -Fq 'max_cpus = 8' "$cohort" || {
  echo "test_run_cohort_launcher: viralintegration max_cpus cap missing" >&2
  exit 1
}
grep -Fq 'max_memory = "20.GB"' "$cohort" || {
  echo "test_run_cohort_launcher: viralintegration max_memory cap missing" >&2
  exit 1
}
grep -Fq -- '-c "$params"' "$cohort" || {
  echo "test_run_cohort_launcher: nextflow params must be passed with -c (not -params-file on NF 26+)" >&2
  exit 1
}
if grep -Fq -- '-params-file "$params"' "$cohort"; then
  echo "test_run_cohort_launcher: must not use deprecated -params-file for cohort runs" >&2
  exit 1
fi
if grep -Fq 'virus_fasta' "$cohort"; then
  echo "test_run_cohort_launcher: old virus_fasta param name must not appear" >&2
  exit 1
fi
grep -Fq 'pipelines.sarek.enabled' "$cohort" || {
  echo "test_run_cohort_launcher: SNP gate should consult sarek.enabled" >&2
  exit 1
}

echo "test_run_cohort_launcher: ok"
