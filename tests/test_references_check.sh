#!/usr/bin/env bash
# references_check / ref_asset stamp and MD5 guards (no network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/ref" "${tmp}/config"

# MD5 of printf 'ACGT\n' | gzip -c and printf 'gene\n' | gzip -c (test fixtures).
FASTA_MD5="8f969ecf131e837c6b1bb7f936cf009b"
GTF_MD5="3c4cd47cd66df7b8a7ce821fca45e769"

cat >"${tmp}/config/pin.yaml" <<YAML
references:
  fasta_url: https://example.invalid/mm39.fa.gz
  fasta_gz: ${tmp}/ref/mm39.fa.gz
  fasta: ${tmp}/ref/mm39.fa
  fasta_md5: ${FASTA_MD5}
  gtf_url: https://example.invalid/mm39.gtf.gz
  gtf_gz: ${tmp}/ref/mm39.gtf.gz
  gtf: ${tmp}/ref/mm39.gtf
  gtf_md5: ${GTF_MD5}
virus:
  bundled_url: https://example.invalid/virus.fa
  bundled_fasta: ${tmp}/ref/virus.fa
  local_dir: ${tmp}/ref/local
  merged_fasta: ${tmp}/ref/viral.fasta
  dedup_report: ${tmp}/ref/dedup.tsv
kraken2_db: ${tmp}/ref/kraken2
pipelines:
  viralintegration:
    name: nf-core/viralintegration
    revision: 0.1.1
nextflow:
  version: "26.10.3"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
YAML

cat >"${tmp}/site.config.yaml" <<YAML
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
mkdir -p "${tmp}/scratch"

printf 'ACGT\n' | gzip -c >"${tmp}/ref/mm39.fa.gz"
printf 'wrong-md5-content\n' >"${tmp}/ref/mm39.fa"
echo "deadbeefdeadbeefdeadbeefdeadbeef" >"${tmp}/ref/mm39.fa.stamp"

ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site.config.yaml"
if ( references_check ) >/dev/null 2>&1; then
  echo "references_check: stamp mismatch should fail" >&2
  exit 1
fi

printf 'ACGT\n' >"${tmp}/ref/mm39.fa"
echo "$FASTA_MD5" >"${tmp}/ref/mm39.fa.stamp"
printf 'gene\n' | gzip -c >"${tmp}/ref/mm39.gtf.gz"
printf 'gene\n' >"${tmp}/ref/mm39.gtf"
echo "$GTF_MD5" >"${tmp}/ref/mm39.gtf.stamp"

references_check

echo "wrong" >"${tmp}/ref/mm39.fa.gz"
if ( references_check ) >/dev/null 2>&1; then
  echo "references_check: gzip MD5 mismatch should fail" >&2
  exit 1
fi

echo "test_references_check: ok"
