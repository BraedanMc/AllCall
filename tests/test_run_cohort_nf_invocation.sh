#!/usr/bin/env bash
# Regression: cohort Nextflow CLI uses -c for params (not -params-file) and VI params use viral_fasta.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "${tmp}/scratch" "${tmp}/results" "${tmp}/opt" "${tmp}/ref/virus"
touch "${tmp}/merged.fasta"
touch "${tmp}/sheet.csv"
printf '#!/bin/sh\necho " NEXTFLOW 24.10.5 "\n' >"${tmp}/opt/nf"
chmod +x "${tmp}/opt/nf"

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
  bin: opt/nf
  home: opt/nxf-home
scratch_root: from_pin
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
pipelines:
  viralintegration:
    name: nf-core/viralintegration
    revision: 0.1.1
  sarek:
    name: nf-core/sarek
    revision: 3.10.0
  viralmetagenome:
    name: nf-core/viralmetagenome
    revision: 1.2.0
YAML

cat >"${tmp}/site.config.yaml" <<YAML
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
    enabled: true
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: docker
nextflow_configs: []
YAML

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"

params="${tmp}/params/vi.config"
cohort_write_viralintegration_params "$params" "${tmp}/sheet.csv" "${tmp}/results/run1/viralintegration" \
  "${tmp}/ref/hg38.fa" "${tmp}/ref/hg38.gtf" "${tmp}/merged.fasta"

grep -q 'viral_fasta' "$params" || {
  echo "test_run_cohort_nf_invocation: expected viral_fasta in viralintegration params" >&2
  exit 1
}
if grep -q 'virus_fasta' "$params"; then
  echo "test_run_cohort_nf_invocation: obsolete virus_fasta must not appear" >&2
  exit 1
fi
grep -q 'max_cpus = 8' "$params" && grep -q 'max_memory = "20.GB"' "$params" || {
  echo "test_run_cohort_nf_invocation: expected max_cpus / max_memory caps" >&2
  exit 1
}

work="$(work_dir viralintegration)"
line="$(nf_cmd "$(pipeline_name viralintegration)" "$(pipeline_revision viralintegration)" "$work" "$params")"

[[ "$line" == *"-c ${params}"* ]] || {
  echo "test_run_cohort_nf_invocation: nf_cmd should pass cohort params with -c (got: ${line})" >&2
  exit 1
}
[[ "$line" != *params-file* ]] || {
  echo "test_run_cohort_nf_invocation: nf_cmd must not use -params-file (got: ${line})" >&2
  exit 1
}
[[ "$line" == *"-profile docker"* ]] || {
  echo "test_run_cohort_nf_invocation: expected -profile docker (got: ${line})" >&2
  exit 1
}

echo "test_run_cohort_nf_invocation: ok"
