#!/usr/bin/env bash
# Regression guards for cohort Nextflow launcher and viralintegration params (NF 24 pin).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cohort="${ROOT}/bin/run_cohort.sh"

grep -q 'viral_fasta = ' "$cohort" || {
  echo "test_run_cohort_regressions: viralintegration params must set viral_fasta (nf-core 0.1.1)" >&2
  exit 1
}
grep -q 'virus_fasta = ' "$cohort" && {
  echo "test_run_cohort_regressions: obsolete virus_fasta param still present" >&2
  exit 1
}

grep -qE '\-c "\$params"' "$cohort" || {
  echo "test_run_cohort_regressions: nf_cmd must pass params with -c (not -params-file)" >&2
  exit 1
}
grep -q '\-params-file' "$cohort" && {
  echo "test_run_cohort_regressions: -params-file must not be used (Nextflow 26 breakage)" >&2
  exit 1
}

grep -q 'max_cpus = 8' "$cohort" || {
  echo "test_run_cohort_regressions: viralintegration max_cpus cap missing" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$cohort" || {
  echo "test_run_cohort_regressions: viralintegration max_memory cap missing" >&2
  exit 1
}

grep -qE "cfg '\.pipelines\.sarek\.enabled'" "$cohort" || {
  echo "test_run_cohort_regressions: SNP gate should consult sarek.enabled" >&2
  exit 1
}

command -v yq >/dev/null 2>&1 || {
  echo "test_run_cohort_regressions: yq required" >&2
  exit 1
}
ver="$(yq -r '.nextflow.version' "${ROOT}/config/pin.yaml")"
[[ "$ver" == "24.10.5" ]] || {
  echo "test_run_cohort_regressions: pin nextflow.version must stay 24.10.5 (got ${ver})" >&2
  exit 1
}

appt="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$appt" ]] || {
  echo "test_run_cohort_regressions: missing ${appt}" >&2
  exit 1
}
grep -q 'enabled = true' "$appt" || {
  echo "test_run_cohort_regressions: apptainer overlay should enable singularity" >&2
  exit 1
}

local_nf="${ROOT}/config/nextflow/local.config"
grep -A3 '^singularity {' "$local_nf" | grep -q 'enabled = false' || {
  echo "test_run_cohort_regressions: local.config must keep singularity disabled for docker profile" >&2
  exit 1
}

echo "test_run_cohort_regressions: ok"
