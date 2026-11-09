#!/usr/bin/env bash
# Regression: cohort Nextflow CLI uses -c for params (NF 26 workaround) and viralintegration param names.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cohort="${ROOT}/bin/run_cohort.sh"

grep -qE '\-c[[:space:]]+"\$params"' "$cohort" || {
  echo "test_run_cohort_nf_cli: nf_cmd must pass generated params with -c" >&2
  exit 1
}
if grep -q 'params-file' "$cohort"; then
  echo "test_run_cohort_nf_cli: must not use -params-file (broken on Nextflow 26)" >&2
  exit 1
fi
grep -q 'viral_fasta' "$cohort" || {
  echo "test_run_cohort_nf_cli: viralintegration params need viral_fasta" >&2
  exit 1
}
if grep -q 'virus_fasta' "$cohort"; then
  echo "test_run_cohort_nf_cli: obsolete virus_fasta param name" >&2
  exit 1
fi
grep -q 'max_cpus' "$cohort" && grep -q 'max_memory' "$cohort" || {
  echo "test_run_cohort_nf_cli: local VI resource caps missing" >&2
  exit 1
}

pin="${ROOT}/config/pin.yaml"
grep -q 'version: "24.10.5"' "$pin" || {
  echo "test_run_cohort_nf_cli: pin must stay on Nextflow 24.10.5 for viralintegration 0.1.1" >&2
  exit 1
}
if grep -q '26.10.3' "$pin"; then
  echo "test_run_cohort_nf_cli: pin must not reference Nextflow 26.10.3" >&2
  exit 1
fi

appt="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$appt" ]] || {
  echo "test_run_cohort_nf_cli: missing local.apptainer.config overlay" >&2
  exit 1
}
grep -q 'enabled = true' "$appt" || {
  echo "test_run_cohort_nf_cli: apptainer overlay should enable singularity" >&2
  exit 1
}

echo "test_run_cohort_nf_cli: ok"
