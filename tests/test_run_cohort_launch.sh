#!/usr/bin/env bash
# Cohort Nextflow launcher: -c params/overlays (not -params-file) and viralintegration caps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
run_cohort="${ROOT}/bin/run_cohort.sh"
lib="${ROOT}/bin/lib.sh"

grep -q 'cohort_nf_cmd' "$run_cohort" || {
  echo "test_run_cohort_launch: run_cohort must use cohort_nf_cmd" >&2
  exit 1
}
grep -q '\-c "\$params"' "$lib" || {
  echo "test_run_cohort_launch: cohort_nf_cmd must pass params with -c" >&2
  exit 1
}
if grep -v '^[[:space:]]*#' "$run_cohort" "$lib" | grep -q 'params-file'; then
  echo "test_run_cohort_launch: must not use -params-file (NF 26 + viralintegration 0.1.1)" >&2
  exit 1
fi
grep -q 'viral_fasta' "$run_cohort" || {
  echo "test_run_cohort_launch: viralintegration params missing viral_fasta" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$run_cohort" || {
  echo "test_run_cohort_launch: viralintegration params missing max_cpus cap" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$run_cohort" || {
  echo "test_run_cohort_launch: viralintegration params missing max_memory cap" >&2
  exit 1
}

apptainer_overlay="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$apptainer_overlay" ]] || {
  echo "test_run_cohort_launch: missing ${apptainer_overlay}" >&2
  exit 1
}
grep -q 'enabled = true' "$apptainer_overlay" || {
  echo "test_run_cohort_launch: apptainer overlay should enable singularity" >&2
  exit 1
}

# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/scratch" "${tmp}/config" "${tmp}/opt"
printf '#!/bin/sh\necho "N E X T F L O W  24.10.5"\n' >"${tmp}/opt/nextflow"
chmod +x "${tmp}/opt/nextflow"

overlay="${tmp}/site/nextflow.overlay.config"
mkdir -p "${tmp}/site"
echo 'process { cpus = 1 }' >"$overlay"

cat >"${tmp}/config/pin.yaml" <<YAML
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
    kraken2_db: ${tmp}/ref/kraken2
pipelines:
  viralintegration:
    name: nf-core/viralintegration
    revision: 0.1.1
nextflow:
  version: "24.10.5"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
work_dirs:
  viralintegration: nfVI
YAML

params_file="${tmp}/params/viralintegration.config"
mkdir -p "$(dirname "$params_file")"
echo 'params { input = "x" }' >"$params_file"

cat >"${tmp}/site.config.yaml" <<YAML
species: human
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${overlay}
YAML

ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site.config.yaml"

[[ "$(cohort_nf_profile)" == "docker" ]] || {
  echo "test_run_cohort_launch: expected docker profile" >&2
  exit 1
}

work="${tmp}/scratch/nfVI"
cmd="$(cohort_nf_cmd nf-core/viralintegration 0.1.1 "$work" "$params_file")"
[[ "$cmd" == *"-c ${params_file}"* ]] || {
  echo "test_run_cohort_launch: cmd missing params -c (got: ${cmd})" >&2
  exit 1
}
[[ "$cmd" == *"-c ${overlay}"* ]] || {
  echo "test_run_cohort_launch: cmd missing site overlay -c (got: ${cmd})" >&2
  exit 1
}
[[ "$cmd" == *"-profile docker"* ]] || {
  echo "test_run_cohort_launch: cmd missing -profile docker (got: ${cmd})" >&2
  exit 1
}
[[ "$cmd" == *params-file* ]] && {
  echo "test_run_cohort_launch: cmd must not contain params-file" >&2
  exit 1
}

ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site.config.yaml"
yq -i '.container_profile = "apptainer"' "$CONFIG_MERGED"
[[ "$(cohort_nf_profile)" == "singularity" ]] || {
  echo "test_run_cohort_launch: apptainer site should map to singularity profile" >&2
  exit 1
}

echo "test_run_cohort_launch: ok"
