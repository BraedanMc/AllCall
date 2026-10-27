#!/usr/bin/env bash
# check_container validates container_profile (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pin="${tmp}/pin.yaml"
cat >"$pin" <<'YAML'
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
scratch_root: scratch
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
YAML

load_site() {
  local profile="$1"
  cat >"${tmp}/site.config.yaml" <<YAML
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
container_profile: ${profile}
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
}

mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

load_site podman
ALLCALL_PIN="$pin" load_config "${tmp}/site.config.yaml"
if ( check_container ) >/dev/null 2>&1; then
  echo "test_check_container: unknown profile should fail" >&2
  exit 1
fi

load_site docker
ALLCALL_PIN="$pin" load_config "${tmp}/site.config.yaml"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  check_container
else
  if ( check_container ) >/dev/null 2>&1; then
    echo "test_check_container: docker profile without usable docker should fail" >&2
    exit 1
  fi
fi

echo "test_check_container: ok"
