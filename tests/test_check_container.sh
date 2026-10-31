#!/usr/bin/env bash
# check_container: reject unknown container_profile (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"${tmp}/pin.yaml" <<'YAML'
species:
  human:
    references:
      fasta_url: https://example.invalid/h.fa.gz
      fasta_gz: ref/h.fa.gz
      fasta: ref/h.fa
      fasta_md5: aa
      gtf_url: https://example.invalid/h.gtf.gz
      gtf_gz: ref/h.gtf.gz
      gtf: ref/h.gtf
      gtf_md5: bb
    kraken2_db: ref/kraken2/human
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
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
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: podman
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
if ( check_container ) >/dev/null 2>&1; then
  echo "test_check_container: unknown profile should die" >&2
  exit 1
fi

echo "test_check_container: ok"
