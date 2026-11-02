#!/usr/bin/env bash
# resolve_species_config: toggle, validation, and per-species reference injection.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

base_pin="${tmp}/pin.yaml"
cat >"$base_pin" <<'YAML'
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
      fasta_gz: ref/mm39/mm39.fa.gz
      fasta: ref/mm39/mm39.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/mm39.gtf.gz
      gtf_gz: ref/mm39/mm39.gtf.gz
      gtf: ref/mm39/mm39.gtf
      gtf_md5: ""
    kraken2_db: ref/kraken2/mm39
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
work_dirs:
  viralintegration: nfVI
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
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
}

mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

cat >"${tmp}/site_default.yaml" <<YAML
$(site_common)
YAML
ALLCALL_PIN="$base_pin" load_config "${tmp}/site_default.yaml"

[[ "$(cfg '.references.fasta_gz')" == "ref/hg38.fa.gz" ]] || {
  echo "species resolve: default human should inject hg38 references" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/hg38" ]] || {
  echo "species resolve: default human kraken2_db wrong" >&2
  exit 1
}

cat >"${tmp}/site_mouse.yaml" <<YAML
species: mouse
$(site_common)
YAML
ALLCALL_PIN="$base_pin" load_config "${tmp}/site_mouse.yaml"
[[ "$(cfg '.references.fasta')" == "ref/mm39/mm39.fa" ]] || {
  echo "species resolve: mouse should inject mm39 references" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mm39" ]] || {
  echo "species resolve: mouse kraken2_db wrong" >&2
  exit 1
}

cat >"${tmp}/site_bad.yaml" <<YAML
species: rat
$(site_common)
YAML
if ( ALLCALL_PIN="$base_pin" load_config "${tmp}/site_bad.yaml" ) >/dev/null 2>&1; then
  echo "species resolve: invalid species should fail" >&2
  exit 1
fi

cat >"${tmp}/pin_incomplete.yaml" <<YAML
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
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
work_dirs:
  viralintegration: nfVI
YAML
cat >"${tmp}/site_human.yaml" <<YAML
species: human
$(site_common)
YAML
if ( ALLCALL_PIN="${tmp}/pin_incomplete.yaml" load_config "${tmp}/site_human.yaml" ) >/dev/null 2>&1; then
  echo "species resolve: missing kraken2_db in pin should fail" >&2
  exit 1
fi

echo "test_species_resolve: ok"
