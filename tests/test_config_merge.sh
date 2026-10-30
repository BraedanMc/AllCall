#!/usr/bin/env bash
# Pin + site YAML merge and path helpers (lib.sh).
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
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
scratch_root: from_pin_should_not_win
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
YAML

cat >"${tmp}/site.config.yaml" <<YAML
scratch_root: ${tmp}/scratch_rel
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
sex_xy_min_ratio: 0.25
nextflow_configs: []
YAML

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"

[[ "$(cfg '.scratch_root')" == "${tmp}/scratch_rel" ]] || {
  echo "config merge: site scratch_root should override pin" >&2
  exit 1
}
[[ "$(cfg '.sex_xy_min_ratio')" == "0.25" ]] || {
  echo "config merge: site sex_xy_min_ratio missing" >&2
  exit 1
}
[[ "$(cfg '.nextflow.version')" == "24.10.5" ]] || {
  echo "config merge: nextflow.version should come from pin" >&2
  exit 1
}

mkdir -p "${tmp}/scratch_rel"
wd="$(work_dir viralintegration)"
[[ "$wd" == "${tmp}/scratch_rel/nfVI" ]] || {
  echo "work_dir: expected ${tmp}/scratch_rel/nfVI got ${wd}" >&2
  exit 1
}

cat >"${tmp}/site_abs.yaml" <<YAML
scratch_root: ${tmp}/scratch_abs
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
mkdir -p "${tmp}/scratch_abs"
ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site_abs.yaml"
[[ "$(work_dir viralintegration)" == "${tmp}/scratch_abs/nfVI" ]] || {
  echo "work_dir: absolute scratch_root path wrong" >&2
  exit 1
}

rel="nested/rel.out"
got="$(abs_path "$rel")"
[[ "$got" == "${PROJECT_ROOT}/nested/rel.out" ]] || {
  echo "abs_path: relative resolution wrong (got ${got})" >&2
  exit 1
}

if ( work_dir unknown_key ) >/dev/null 2>&1; then
  echo "work_dir: should fail for unknown name" >&2
  exit 1
fi

cat >"${tmp}/bad_species.yaml" <<YAML
species: platypus
scratch_root: ${tmp}/scratch_rel
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
if ( ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/bad_species.yaml" ) >/dev/null 2>&1; then
  echo "config merge: invalid species should fail load_config" >&2
  exit 1
fi

echo "test_config_merge: ok"
