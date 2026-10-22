#!/usr/bin/env bash
# Samplesheet parsing and validation (write_sheets.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/config" "${tmp}/sheets"

yq "
  .references.fasta_gz = \"${tmp}/ref/mm39.fa.gz\" |
  .references.fasta = \"${tmp}/ref/mm39.fa\" |
  .references.gtf_gz = \"${tmp}/ref/mm39.gtf.gz\" |
  .references.gtf = \"${tmp}/ref/mm39.gtf\" |
  .virus.bundled_fasta = \"${tmp}/ref/virus/ctat.fasta\" |
  .virus.local_dir = \"${tmp}/ref/virus/local\" |
  .virus.merged_fasta = \"${tmp}/ref/virus/viral.fasta\" |
  .virus.dedup_report = \"${tmp}/ref/virus/dedup.tsv\" |
  .kraken2_db = \"${tmp}/ref/kraken2/mm39\" |
  .nextflow.bin = \"${tmp}/opt/nextflow\" |
  .nextflow.home = \"${tmp}/opt/nxf-home\"
" "${ROOT}/config/pin.yaml" >"${tmp}/config/pin.yaml"

cat >"${tmp}/site.config.yaml" <<YAML
scratch_root: ${scratch}
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
    enabled: true
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: true
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "write_sheets: expected failure for ${label}" >&2
    exit 1
  fi
}

echo "bad,header,here" >"${tmp}/cohort.csv"
expect_fail "bad header" \
  env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/write_sheets.sh" "${tmp}/site.config.yaml" "${tmp}/sheets" 0

cat >"${tmp}/cohort.csv" <<CSV
sample,fastq_1,fastq_2
S1,${tmp}/r1.fastq,${tmp}/r2.fastq.gz
CSV
expect_fail "fastq_1 extension" \
  env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/write_sheets.sh" "${tmp}/site.config.yaml" "${tmp}/sheets" 0

cat >"${tmp}/cohort.csv" <<CSV
sample,fastq_1,fastq_2,lane
S1,${tmp}/a.fastq.gz,${tmp}/b.fastq.gz,1
S1,${tmp}/c.fastq.gz,${tmp}/d.fastq.gz,1
CSV
expect_fail "duplicate lane" \
  env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/write_sheets.sh" "${tmp}/site.config.yaml" "${tmp}/sheets" 0

touch "${tmp}/lane1_r1.fastq.gz" "${tmp}/lane1_r2.fastq.gz" \
  "${tmp}/lane2_r1.fastq.gz" "${tmp}/lane2_r2.fastq.gz"
cat >"${tmp}/cohort.csv" <<CSV
sample,fastq_1,fastq_2,lane
S1,${tmp}/lane1_r1.fastq.gz,${tmp}/lane1_r2.fastq.gz,1
S1,${tmp}/lane2_r1.fastq.gz,${tmp}/lane2_r2.fastq.gz,2
CSV
mkdir -p "${tmp}/sheets_lane"
out="$(env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/write_sheets.sh" "${tmp}/site.config.yaml" "${tmp}/sheets_lane" 0)"
grep -q "sarek_sv_samplesheet.csv" <<<"$out"
grep -q ',2,' "${tmp}/sheets_lane/sarek_sv_samplesheet.csv" || {
  echo "write_sheets: lane column not propagated to sarek sheet" >&2
  exit 1
}

echo "test_write_sheets_validation: ok"
