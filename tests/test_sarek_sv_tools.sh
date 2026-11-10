#!/usr/bin/env bash
# Sarek SV pass: merge tools_sv and optional tools_cnv for nf-core --tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"${tmp}/pin.yaml" <<YAML
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ${tmp}/ref/hg38.fa.gz
      fasta: ${tmp}/ref/hg38.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ${tmp}/ref/hg38.gtf.gz
      gtf: ${tmp}/ref/hg38.gtf
      gtf_md5: ""
    kraken2_db: ${tmp}/ref/kraken2/hg38
virus:
  bundled_fasta: ${tmp}/ref/virus/ctat.fasta
  local_dir: ${tmp}/ref/virus/local
  merged_fasta: ${tmp}/ref/virus/viral.fasta
  dedup_report: ${tmp}/ref/virus/dedup.tsv
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
YAML
mkdir -p "${tmp}/ref/virus/local" "${tmp}/ref/kraken2/hg38"
touch "${tmp}/ref/hg38.fa" "${tmp}/ref/hg38.gtf"

write_site() {
  cat >"${tmp}/site.config.yaml"
}

ALLCALL_PIN="${tmp}/pin.yaml"

write_site <<YAML
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
    enabled: true
    tools_sv: manta
    tools_cnv: cnvkit
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
[[ "$(sarek_sv_tools)" == "manta,cnvkit" ]] || {
  echo "test_sarek_sv_tools: expected manta,cnvkit" >&2
  exit 1
}

write_site <<YAML
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
    enabled: true
    tools_sv: manta,cnvkit
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
[[ "$(sarek_sv_tools)" == "manta,cnvkit" ]] || {
  echo "test_sarek_sv_tools: duplicate cnv in tools_sv should not double" >&2
  exit 1
}

write_site <<YAML
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
    enabled: true
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
[[ "$(sarek_sv_tools)" == "manta" ]] || {
  echo "test_sarek_sv_tools: expected manta only when tools_cnv omitted" >&2
  exit 1
}

echo "test_sarek_sv_tools: ok"
