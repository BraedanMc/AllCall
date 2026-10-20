#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v shellcheck >/dev/null; then
  shellcheck bin/*.sh
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/data"

cat >"${tmp}/bundled.fa" <<'FA'
>KeepMe
ACGT
>OverrideMe
AAAA
FA
cat >"${tmp}/ref/virus/local/NewVirus.fa" <<'FA'
>NewVirus
CCCC
FA
cat >"${tmp}/ref/virus/local/OverrideMe.fa" <<'FA'
>OverrideMe
TTTT
FA

cat >"${tmp}/config.yaml" <<YAML
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
references:
  fasta_url: https://example.invalid/mm39.fa.gz
  fasta_gz: ${tmp}/ref/mm39.fa.gz
  fasta: ${tmp}/ref/mm39.fa
  fasta_md5: 41ace1b7157b98b393746aef5d1287a8
  gtf_url: https://example.invalid/mm39.gtf.gz
  gtf_gz: ${tmp}/ref/mm39.gtf.gz
  gtf: ${tmp}/ref/mm39.gtf
  gtf_md5: 25e15ef5bdd7afc6d3447a757e5fa487
virus:
  bundled_url: https://example.invalid/virus.fa
  bundled_fasta: ${tmp}/ref/virus/ctat.fasta
  local_dir: ${tmp}/ref/virus/local
  merged_fasta: ${tmp}/ref/virus/viral.fasta
  dedup_report: ${tmp}/ref/virus/dedup.tsv
kraken2_db: ${tmp}/ref/kraken2/mm39
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: true
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: true
nextflow:
  version: "25.10.7"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

cp "${tmp}/bundled.fa" "${tmp}/ref/virus/ctat.fasta"
echo "gzip test" | gzip -c >"${tmp}/ref/mm39.fa.gz"
# Use known md5 from config only if we set matching content - skip ref download test
printf 'ACGT\n' >"${tmp}/ref/mm39.fa"
echo "41ace1b7157b98b393746aef5d1287a8" >"${tmp}/ref/mm39.fa.stamp"
cat >"${tmp}/ref/mm39.gtf" <<'GTF'
chr1	source	gene	1	100	.	+	.	.
chr1	source	CDS	10	20	.	+	0	.
GTF
echo "25e15ef5bdd7afc6d3447a757e5fa487" >"${tmp}/ref/mm39.gtf.stamp"

touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

"${ROOT}/bin/merge_virus_fasta.sh" "${tmp}/config.yaml"
grep -q replaced "${tmp}/ref/virus/dedup.tsv"
grep -q TTTT "${tmp}/ref/virus/viral.fasta"

"${ROOT}/bin/write_sheets.sh" "${tmp}/config.yaml" "${tmp}/sheets" 0
test -f "${tmp}/sheets/viralintegration_samplesheet.csv"

"${ROOT}/bin/cds_bed.sh" "${tmp}/ref/mm39.gtf" "${tmp}/cds.bed" 10
test -s "${tmp}/cds.bed"

echo "smoke: ok"
