#!/usr/bin/env bash
# CDS filter must pass host FASTA when decoding Sarek CRAM on the orchestrator host.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

grep -q 'ref_fasta=.*references\.fasta' "${ROOT}/bin/run_cohort.sh" || {
  echo "test_cohort_cds_cram_ref: run_cohort.sh missing ref_fasta from config" >&2
  exit 1
}

grep -q 'samtools view -b -T "\$ref_fasta" -L "\$bed_path" "\$sv_bam"' "${ROOT}/bin/run_cohort.sh" || {
  echo "test_cohort_cds_cram_ref: samtools view must use -T ref_fasta for CRAM decode" >&2
  exit 1
}

echo "test_cohort_cds_cram_ref: ok"
