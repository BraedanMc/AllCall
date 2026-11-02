#!/usr/bin/env bash
# check_container: reject unknown container_profile values early in setup/check.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/scratch"

cat >"${tmp}/pin.yaml" <<YAML
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ref/hg38.fa.gz
      fasta: ref/hg38.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ref/hg38.gtf.gz
      gtf: ref/hg38.gtf
      gtf_md5: ""
    kraken2_db: ref/kraken2/hg38
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
work_dirs:
  viralintegration: nfVI
YAML

cat >"${tmp}/site.config.yaml" <<YAML
species: human
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: false
container_profile: podman
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
if ( check_container ) >/dev/null 2>&1; then
  echo "test_check_container: unknown profile should fail" >&2
  exit 1
fi

echo "test_check_container: ok"
