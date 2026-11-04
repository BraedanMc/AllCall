#!/usr/bin/env bash
# resolve_species_config: toggle, defaults, and pin validation (lib.sh).
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
      fasta_md5: human-md5-marker
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ref/hg38.gtf.gz
      gtf: ref/hg38.gtf
      gtf_md5: human-gtf-md5
    kraken2_db: ref/kraken2/hg38
  mouse:
    references:
      fasta_url: https://example.invalid/mm39.fa.gz
      fasta_gz: ref/mm39.fa.gz
      fasta: ref/mm39.fa
      fasta_md5: mouse-md5-marker
      gtf_url: https://example.invalid/mm39.gtf.gz
      gtf_gz: ref/mm39.gtf.gz
      gtf: ref/mm39.gtf
      gtf_md5: mouse-gtf-md5
    kraken2_db: ref/kraken2/mm39
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
YAML

site_common() {
  cat <<YAML
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
}

mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

cat >"${tmp}/site_mouse.yaml" <<YAML
species: mouse
$(site_common)
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_mouse.yaml"
[[ "$(cfg '.references.fasta_md5')" == "mouse-md5-marker" ]] || {
  echo "species: mouse references not applied (got $(cfg '.references.fasta_md5'))" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mm39" ]] || {
  echo "species: mouse kraken2_db not applied" >&2
  exit 1
}

cat >"${tmp}/site_default.yaml" <<YAML
$(site_common)
YAML
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_default.yaml"
[[ "$(cfg '.references.fasta_md5')" == "human-md5-marker" ]] || {
  echo "species: default should be human references" >&2
  exit 1
}

cat >"${tmp}/site_bad.yaml" <<YAML
species: platypus
$(site_common)
YAML
if ( ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_bad.yaml" ) 2>/dev/null; then
  echo "species: invalid species should fail load_config" >&2
  exit 1
fi

cat >"${tmp}/pin_incomplete.yaml" <<'YAML'
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ref/hg38.fa.gz
      fasta: ref/hg38.fa
      fasta_md5: human-md5-marker
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ref/hg38.gtf.gz
      gtf: ref/hg38.gtf
      gtf_md5: human-gtf-md5
    kraken2_db: ref/kraken2/hg38
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
YAML
cat >"${tmp}/site_mouse2.yaml" <<YAML
species: mouse
$(site_common)
YAML
if ( ALLCALL_PIN="${tmp}/pin_incomplete.yaml" load_config "${tmp}/site_mouse2.yaml" ) 2>/dev/null; then
  echo "species: missing mouse pin block should fail" >&2
  exit 1
fi

echo "test_species_config: ok"
