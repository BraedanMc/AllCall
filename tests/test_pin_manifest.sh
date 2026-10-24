#!/usr/bin/env bash
# Pin manifest regression guards (UCSC hg38 GTF MD5, Nextflow version for VI 0.1.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="${ROOT}/config/pin.yaml"

# Updated 2026-10-22 when UCSC rotated hg38.ncbiRefSeq.gtf.gz (see commit 3cbe108).
HUMAN_GTF_MD5="6a585655a3e67150264b792b758372a2"
got="$(yq -r '.species.human.references.gtf_md5' "$PIN")"
[[ "$got" == "$HUMAN_GTF_MD5" ]] || {
  echo "test_pin_manifest: human gtf_md5 expected ${HUMAN_GTF_MD5} got ${got}" >&2
  exit 1
}

nf_ver="$(yq -r '.nextflow.version' "$PIN")"
[[ "$nf_ver" == "24.10.5" ]] || {
  echo "test_pin_manifest: nextflow.version should stay 24.10.5 for viralintegration 0.1.1 (got ${nf_ver})" >&2
  exit 1
}

cohort="${ROOT}/bin/run_cohort.sh"
grep -q 'viral_fasta' "$cohort" || {
  echo "test_pin_manifest: run_cohort should pass viral_fasta to VI (not virus_fasta)" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$cohort" || {
  echo "test_pin_manifest: run_cohort missing VI max_cpus cap" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$cohort" || {
  echo "test_pin_manifest: run_cohort missing VI max_memory cap" >&2
  exit 1
}

apptainer="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$apptainer" ]] || {
  echo "test_pin_manifest: missing local.apptainer.config overlay" >&2
  exit 1
}
grep -q 'enabled = true' "$apptainer" || {
  echo "test_pin_manifest: apptainer overlay should enable singularity" >&2
  exit 1
}

echo "test_pin_manifest: ok"
