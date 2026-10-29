#!/usr/bin/env bash
# species toggle validation in load_config / resolve_species_config.
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
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ref/hg38.fa.gz
      fasta: ref/hg38.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ref/hg38.gtf.gz
      gtf: ref/hg38.gtf
      gtf_md5: ""
    kraken2_db: ref/kraken2/hg38
  mouse:
    references:
      fasta_url: https://example.invalid/mm39.fa.gz
      fasta_gz: ref/mm39.fa.gz
      fasta: ref/mm39.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/mm39.gtf.gz
      gtf_gz: ref/mm39.gtf.gz
      gtf: ref/mm39.gtf
      gtf_md5: ""
    kraken2_db: ref/kraken2/mm39
scratch_root: scratch
work_dirs:
  viralintegration: nfVI
samplesheet: samplesheets/cohort.csv
results_dir: results
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

base_site() {
  cat <<YAML
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
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
}

mkdir -p "${tmp}/scratch"
touch "${tmp}/cohort.csv"

cat >"${tmp}/site_mouse.yaml" <<YAML
species: mouse
$(base_site)
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_mouse.yaml"
[[ "$(cfg '.references.fasta')" == "ref/mm39.fa" ]] || {
  echo "resolve_species: mouse references not applied" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mm39" ]] || {
  echo "resolve_species: mouse kraken2_db not applied" >&2
  exit 1
}

cat >"${tmp}/site_default.yaml" <<YAML
$(base_site)
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_default.yaml"
[[ "$(cfg '.references.fasta')" == "ref/hg38.fa" ]] || {
  echo "resolve_species: default species should be human" >&2
  exit 1
}

cat >"${tmp}/site_bad.yaml" <<YAML
species: zebra
$(base_site)
YAML
if ( ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_bad.yaml" ) >/dev/null 2>&1; then
  echo "resolve_species: invalid species should fail" >&2
  exit 1
fi

echo "test_resolve_species: ok"
