#!/usr/bin/env bash
# Virus FASTA merge semantics and --check-only staleness.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/config"

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
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

cat >"${tmp}/ref/virus/ctat.fasta" <<'FA'
>DupName
AAAA
>DupName
BBBB
FA

if env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/merge_virus_fasta.sh" "${tmp}/site.config.yaml" 2>/dev/null; then
  echo "virus merge: duplicate bundled name should fail" >&2
  exit 1
fi

cat >"${tmp}/ref/virus/ctat.fasta" <<'FA'
>KeepMe
ACGT
FA
cat >"${tmp}/ref/virus/local/Added.fa" <<'FA'
>AddedLocal
GGGG
FA

env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/merge_virus_fasta.sh" "${tmp}/site.config.yaml"
grep -q AddedLocal "${tmp}/ref/virus/viral.fasta"

env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/merge_virus_fasta.sh" --check-only "${tmp}/site.config.yaml"

echo "STALE" >>"${tmp}/ref/virus/viral.fasta"
if env ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/merge_virus_fasta.sh" --check-only "${tmp}/site.config.yaml" 2>/dev/null; then
  echo "virus merge: --check-only should fail when merged FASTA is stale" >&2
  exit 1
fi

echo "test_virus_merge: ok"
