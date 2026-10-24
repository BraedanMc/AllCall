#!/usr/bin/env bash
# resolve_species_config: toggle, validation, and per-species pin lookup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/config" "${tmp}/scratch"

cat >"${tmp}/config/pin.yaml" <<'YAML'
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
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
YAML

site_base() {
  cat <<YAML
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
}

cat >"${tmp}/site_default.yaml" <<YAML
$(site_base)
YAML
ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site_default.yaml"
[[ "$(cfg '.references.fasta_gz')" == "ref/hg38.fa.gz" ]] || {
  echo "species resolve: default species should be human refs" >&2
  exit 1
}

cat >"${tmp}/site_mouse.yaml" <<YAML
species: mouse
$(site_base)
YAML
ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site_mouse.yaml"
[[ "$(cfg '.references.fasta_gz')" == "ref/mm39.fa.gz" ]] || {
  echo "species resolve: mouse refs not applied" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mm39" ]] || {
  echo "species resolve: mouse kraken2_db not applied" >&2
  exit 1
}

cat >"${tmp}/site_bad.yaml" <<YAML
species: zebrafish
$(site_base)
YAML
if ( ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site_bad.yaml" ) >/dev/null 2>&1; then
  echo "species resolve: invalid species should die" >&2
  exit 1
fi

cat >"${tmp}/pin_human_only.yaml" <<'YAML'
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
YAML
cat >"${tmp}/site_mouse_no_pin.yaml" <<YAML
species: mouse
$(site_base)
YAML
if ( ALLCALL_PIN="${tmp}/pin_human_only.yaml" load_config "${tmp}/site_mouse_no_pin.yaml" ) >/dev/null 2>&1; then
  echo "species resolve: mouse with human-only pin should die" >&2
  exit 1
fi

echo "test_species_resolve: ok"
