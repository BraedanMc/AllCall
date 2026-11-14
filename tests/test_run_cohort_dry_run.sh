#!/usr/bin/env bash
# run_cohort.sh --dry-run: Nextflow -c params, VI viral_fasta caps, and launch set.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/data" "${tmp}/config" "${tmp}/bin" "${tmp}/opt/nxf-home"
cp "${ROOT}/bin/"*.sh "${tmp}/bin/"
chmod +x "${tmp}/bin/"*.sh
cat >"${tmp}/bin/check.sh" <<'EOF'
#!/usr/bin/env bash
echo "check: ok"
EOF
chmod +x "${tmp}/bin/check.sh"

FASTA_MD5="1c9dcaddfa41027f17cd8f7a82c7293b"
GTF_MD5="15e6cab3a16e87f2564839f7500700e2"

yq "
  .species.human.references.fasta_gz = \"${tmp}/ref/hg38.fa.gz\" |
  .species.human.references.fasta = \"${tmp}/ref/hg38.fa\" |
  .species.human.references.gtf_gz = \"${tmp}/ref/hg38.gtf.gz\" |
  .species.human.references.gtf = \"${tmp}/ref/hg38.gtf\" |
  .species.human.references.fasta_md5 = \"${FASTA_MD5}\" |
  .species.human.references.gtf_md5 = \"${GTF_MD5}\" |
  .species.human.kraken2_db = \"${tmp}/ref/kraken2/hg38\" |
  .virus.bundled_fasta = \"${tmp}/ref/virus/ctat.fasta\" |
  .virus.local_dir = \"${tmp}/ref/virus/local\" |
  .virus.merged_fasta = \"${tmp}/ref/virus/viral.fasta\" |
  .virus.dedup_report = \"${tmp}/ref/virus/dedup.tsv\" |
  .nextflow.bin = \"${tmp}/opt/nextflow\" |
  .nextflow.home = \"${tmp}/opt/nxf-home\" |
  .nextflow.version = \"24.10.5\"
" "${ROOT}/config/pin.yaml" >"${tmp}/config/pin.yaml"

printf '#!/bin/sh\necho "nextflow version 24.10.5"\n' >"${tmp}/opt/nextflow"
chmod +x "${tmp}/opt/nextflow"

echo "gzip" | gzip -c >"${tmp}/ref/hg38.fa.gz"
printf 'ACGT\n' >"${tmp}/ref/hg38.fa"
echo "$FASTA_MD5" >"${tmp}/ref/hg38.fa.stamp"
cat >"${tmp}/ref/hg38.gtf" <<'GTF'
chr1	source	gene	1	100	.	+	.	.
chr1	source	CDS	10	20	.	+	0	.
GTF
echo "$GTF_MD5" >"${tmp}/ref/hg38.gtf.stamp"
echo "gzip" | gzip -c >"${tmp}/ref/hg38.gtf.gz"
printf ">v\nA\n" >"${tmp}/ref/virus/ctat.fasta"
printf ">v\nA\n" >"${tmp}/ref/virus/viral.fasta"

touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

mk_site_config() {
  local sarek="$1" vi="$2" vm="$3" outfile="$4"
  cat >"$outfile" <<YAML
species: human
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
    enabled: ${vi}
  sarek:
    enabled: ${sarek}
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: ${vm}
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${ROOT}/config/nextflow/local.config
YAML
}

mk_site_config true true false "${tmp}/site.config.yaml"
run_root="${tmp}/results/cohort01"
mapfile -t nf_lines < <(
  ALLCALL_PIN="${tmp}/config/pin.yaml" \
    "${tmp}/bin/run_cohort.sh" --config "${tmp}/site.config.yaml" --run-name cohort01 --dry-run 2>/dev/null
)

[[ "${#nf_lines[@]}" -ge 2 ]] || {
  echo "test_run_cohort_dry_run: expected multiple nextflow run lines" >&2
  exit 1
}

joined="$(printf '%s\n' "${nf_lines[@]}")"
grep -q -- '-params-file' <<<"$joined" && {
  echo "test_run_cohort_dry_run: must use -c for cohort params, not -params-file" >&2
  exit 1
}
grep -q 'viralintegration' <<<"$joined" || {
  echo "test_run_cohort_dry_run: missing viralintegration launch line" >&2
  exit 1
}
grep -q 'sarek' <<<"$joined" || {
  echo "test_run_cohort_dry_run: missing sarek launch line" >&2
  exit 1
}

vi_cfg="${run_root}/params/viralintegration.config"
[[ -f "$vi_cfg" ]] || {
  echo "test_run_cohort_dry_run: missing ${vi_cfg}" >&2
  exit 1
}
grep -q 'viral_fasta' "$vi_cfg" || {
  echo "test_run_cohort_dry_run: viralintegration params need viral_fasta" >&2
  exit 1
}
grep -q 'virus_fasta' "$vi_cfg" && {
  echo "test_run_cohort_dry_run: obsolete virus_fasta must not appear" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$vi_cfg" || {
  echo "test_run_cohort_dry_run: expected max_cpus cap in VI params" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$vi_cfg" || {
  echo "test_run_cohort_dry_run: expected max_memory cap in VI params" >&2
  exit 1
}

matrix="${run_root}/matrix.tsv"
[[ -f "$matrix" ]] || {
  echo "test_run_cohort_dry_run: dry-run should write matrix.tsv" >&2
  exit 1
}
grep -q $'S1\trunning' "$matrix" || {
  echo "test_run_cohort_dry_run: matrix should mark VI/SV running in dry-run" >&2
  exit 1
}

rm -rf "${tmp}/results"
mk_site_config false true false "${tmp}/site.vi-only.yaml"
mapfile -t vi_only_lines < <(
  ALLCALL_PIN="${tmp}/config/pin.yaml" \
    "${tmp}/bin/run_cohort.sh" --config "${tmp}/site.vi-only.yaml" --run-name vi01 --dry-run 2>/dev/null
)
vi_only="$(printf '%s\n' "${vi_only_lines[@]}")"
grep -q 'nfSarekSV' <<<"$vi_only" && {
  echo "test_run_cohort_dry_run: must not launch Sarek SV when pipelines.sarek.enabled is false" >&2
  exit 1
}
grep -q 'nf-core/viralintegration' <<<"$vi_only" || {
  echo "test_run_cohort_dry_run: VI-only config should still launch viralintegration" >&2
  exit 1
}
# SNP command is always emitted; runtime gate checks pipelines.sarek.enabled before eval.
grep -q 'nfSarekSNP' <<<"$vi_only" || {
  echo "test_run_cohort_dry_run: expected prebuilt SNP launch line" >&2
  exit 1
}

echo "test_run_cohort_dry_run: ok"