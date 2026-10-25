#!/usr/bin/env bash
# run_cohort.sh dry-run: Nextflow -c params, VI caps, viral_fasta, overlay configs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/data" "${tmp}/config" "${tmp}/opt"

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
    kraken2_db: ${tmp}/ref/kraken2/hg38
virus:
  bundled_url: https://example.invalid/virus.fa
  bundled_fasta: ${tmp}/ref/virus/ctat.fasta
  local_dir: ${tmp}/ref/virus/local
  merged_fasta: ${tmp}/ref/virus/viral.fasta
  dedup_report: ${tmp}/ref/virus/dedup.tsv
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
nextflow:
  version: "24.10.5"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
YAML

cat >"${tmp}/opt/nextflow" <<'NF'
#!/usr/bin/env bash
echo "nextflow version 24.10.5"
NF
chmod +x "${tmp}/opt/nextflow"

echo "gzip test" | gzip -c >"${tmp}/ref/hg38.fa.gz"
printf 'ACGT\n' >"${tmp}/ref/hg38.fa"
cat >"${tmp}/ref/hg38.gtf" <<'GTF'
chr1	source	gene	1	100	.	+	.	.
chr1	source	CDS	10	20	.	+	0	.
GTF
printf '>v\nA\n' >"${tmp}/ref/virus/ctat.fasta"
printf '>v\nA\n' >"${tmp}/ref/virus/viral.fasta"
printf 'id\taction\n' >"${tmp}/ref/virus/dedup.tsv"

touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

overlay="${ROOT}/config/nextflow/local.config"
cat >"${tmp}/site.config.yaml" <<YAML
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
    enabled: true
  sarek:
    enabled: false
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${overlay}
YAML

run_out="$(
  env ALLCALL_PIN="${tmp}/config/pin.yaml" ALLCALL_SKIP_COHORT_CHECK=1 \
    "${ROOT}/bin/run_cohort.sh" --config "${tmp}/site.config.yaml" --run-name nf_test --dry-run
)"

if grep -q -- '-params-file' <<<"$run_out"; then
  echo "test_run_cohort_nf_invoke: expected -c params config, not -params-file" >&2
  exit 1
fi
if ! grep -q -- '-c .*params/viralintegration.config' <<<"$run_out"; then
  echo "test_run_cohort_nf_invoke: dry-run missing -c viralintegration params" >&2
  exit 1
fi
if ! grep -q -- "-c ${overlay}" <<<"$run_out"; then
  echo "test_run_cohort_nf_invoke: dry-run missing nextflow_configs overlay -c" >&2
  exit 1
fi

vi_params="${tmp}/results/nf_test/params/viralintegration.config"
[[ -f "$vi_params" ]] || {
  echo "test_run_cohort_nf_invoke: missing ${vi_params}" >&2
  exit 1
}
grep -q 'viral_fasta' "$vi_params" || {
  echo "test_run_cohort_nf_invoke: viralintegration params need viral_fasta (not virus_fasta)" >&2
  exit 1
}
grep -q 'virus_fasta' "$vi_params" && {
  echo "test_run_cohort_nf_invoke: obsolete virus_fasta param present" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$vi_params" || {
  echo "test_run_cohort_nf_invoke: missing max_cpus cap" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$vi_params" || {
  echo "test_run_cohort_nf_invoke: missing max_memory cap" >&2
  exit 1
}

apptainer_overlay="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$apptainer_overlay" ]] || {
  echo "test_run_cohort_nf_invoke: missing ${apptainer_overlay}" >&2
  exit 1
}
grep -q 'enabled = true' "$apptainer_overlay" || {
  echo "test_run_cohort_nf_invoke: apptainer overlay should enable singularity" >&2
  exit 1
}

cat >"${tmp}/site.apptainer.yaml" <<YAML
species: human
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results_apptainer
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: apptainer
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${overlay}
  - ${apptainer_overlay}
YAML

app_out="$(
  env ALLCALL_PIN="${tmp}/config/pin.yaml" ALLCALL_SKIP_COHORT_CHECK=1 \
    "${ROOT}/bin/run_cohort.sh" --config "${tmp}/site.apptainer.yaml" --run-name nf_app --dry-run
)"
if ! grep -q -- '-profile singularity' <<<"$app_out"; then
  echo "test_run_cohort_nf_invoke: apptainer site should use -profile singularity" >&2
  exit 1
fi
if ! grep -q -- "-c ${apptainer_overlay}" <<<"$app_out"; then
  echo "test_run_cohort_nf_invoke: apptainer overlay missing from nf_cmd" >&2
  exit 1
fi

echo "test_run_cohort_nf_invoke: ok"
