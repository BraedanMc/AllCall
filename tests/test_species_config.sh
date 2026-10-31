#!/usr/bin/env bash
# resolve_species_config: toggle validation and per-species pin merge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pin_base() {
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
  mouse:
    references:
      fasta_url: https://example.invalid/m.fa.gz
      fasta_gz: ref/m.fa.gz
      fasta: ref/m.fa
      fasta_md5: cc
      gtf_url: https://example.invalid/m.gtf.gz
      gtf_gz: ref/m.gtf.gz
      gtf: ref/m.gtf
      gtf_md5: dd
    kraken2_db: ref/kraken2/mouse
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
}

site_minimal() {
  local species="${1:-human}"
  cat >"${tmp}/site.config.yaml" <<YAML
species: ${species}
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
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
  mkdir -p "${tmp}/scratch"
  echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
}

expect_load_fail() {
  local label="$1"
  if ( ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml" ) >/dev/null 2>&1; then
    echo "test_species_config: ${label} should fail load_config" >&2
    exit 1
  fi
}

pin_base
site_minimal rat
expect_load_fail "invalid species rat"

pin_base
site_minimal mouse
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
[[ "$(cfg '.references.fasta')" == "ref/m.fa" ]] || {
  echo "test_species_config: mouse fasta path wrong" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mouse" ]] || {
  echo "test_species_config: mouse kraken2_db wrong" >&2
  exit 1
}

yq -i 'del(.species.mouse)' "${tmp}/pin.yaml"
site_minimal mouse
expect_load_fail "mouse selected but missing pin.species.mouse"

echo "test_species_config: ok"
