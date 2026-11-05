#!/usr/bin/env bash
# Nextflow 26 workaround: cohort launcher must pass params via -c and use viralintegration param names.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/bin/run_cohort.sh"

grep -qE '\-c "\$params"' "$SCRIPT" || {
  echo "test_run_cohort_nextflow_cli: nf_cmd must pass generated params with -c" >&2
  exit 1
}
if grep -q '\-params-file' "$SCRIPT"; then
  echo "test_run_cohort_nextflow_cli: must not use -params-file (breaks NF 26 / viralintegration)" >&2
  exit 1
fi
grep -q 'viral_fasta' "$SCRIPT" || {
  echo "test_run_cohort_nextflow_cli: viralintegration params need viral_fasta" >&2
  exit 1
}
if grep -q 'virus_fasta' "$SCRIPT"; then
  echo "test_run_cohort_nextflow_cli: obsolete virus_fasta param name" >&2
  exit 1
fi
grep -q 'max_cpus = 8' "$SCRIPT" || {
  echo "test_run_cohort_nextflow_cli: missing viralintegration max_cpus cap" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$SCRIPT" || {
  echo "test_run_cohort_nextflow_cli: missing viralintegration max_memory cap" >&2
  exit 1
}

nf_ver="$(yq -r '.nextflow.version' "${ROOT}/config/pin.yaml")"
[[ "$nf_ver" == "24.10.5" ]] || {
  echo "test_run_cohort_nextflow_cli: expected nextflow.version 24.10.5 in pin (got ${nf_ver})" >&2
  exit 1
}

echo "test_run_cohort_nextflow_cli: ok"
