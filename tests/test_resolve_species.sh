#!/usr/bin/env bash
# resolve_species_config: species toggle and validation (lib.sh).
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
scratch_root: scratch
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
YAML

site_base() {
  cat <<'SITEYAML'
scratch_root: __SCRATCH__
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: __COHORT__
results_dir: __RESULTS__
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
SITEYAML
}

write_site() {
  local dest="$1" species_line="${2:-}"
  {
    [[ -n "$species_line" ]] && echo "$species_line"
    site_base | sed \
      -e "s|__SCRATCH__|${tmp}/scratch|g" \
      -e "s|__COHORT__|${tmp}/cohort.csv|g" \
      -e "s|__RESULTS__|${tmp}/results|g"
  } >"$dest"
}

mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

write_site "${tmp}/bad.species.yaml" "species: zebrafish"

if ( ALLCALL_PIN="$pin" load_config "${tmp}/bad.species.yaml" ) >/dev/null 2>&1; then
  echo "test_resolve_species: invalid species should fail load_config" >&2
  exit 1
fi

write_site "${tmp}/mouse.yaml" "species: mouse"

ALLCALL_PIN="$pin" load_config "${tmp}/mouse.yaml"
[[ "$(cfg '.references.fasta')" == "ref/mm39.fa" ]] || {
  echo "test_resolve_species: mouse fasta path wrong (got $(cfg '.references.fasta'))" >&2
  exit 1
}
[[ "$(cfg '.kraken2_db')" == "ref/kraken2/mm39" ]] || {
  echo "test_resolve_species: mouse kraken2_db wrong" >&2
  exit 1
}

write_site "${tmp}/default.yaml"

ALLCALL_PIN="$pin" load_config "${tmp}/default.yaml"
[[ "$(cfg '.references.fasta')" == "ref/hg38.fa" ]] || {
  echo "test_resolve_species: default species should be human" >&2
  exit 1
}

echo "test_resolve_species: ok"
