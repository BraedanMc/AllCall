#!/usr/bin/env bash
# run_cohort.sh --dry-run: Nextflow -c params, VI caps, and enabled-pipeline launch lines.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/tmp:${PATH}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/data" "${tmp}/config" "${tmp}/results"

fasta_md5="1c9dcaddfa41027f17cd8f7a82c7293b"
gtf_md5="15e6cab3a16e87f2564839f7500700e2"

yq "
  .species.human.references.fasta_gz = \"${tmp}/ref/hg38.fa.gz\" |
  .species.human.references.fasta = \"${tmp}/ref/hg38.fa\" |
  .species.human.references.gtf_gz = \"${tmp}/ref/hg38.gtf.gz\" |
  .species.human.references.gtf = \"${tmp}/ref/hg38.gtf\" |
  .species.human.kraken2_db = \"${tmp}/ref/kraken2/hg38\" |
  .virus.bundled_fasta = \"${tmp}/ref/virus/ctat.fasta\" |
  .virus.local_dir = \"${tmp}/ref/virus/local\" |
  .virus.merged_fasta = \"${tmp}/ref/virus/viral.fasta\" |
  .virus.dedup_report = \"${tmp}/ref/virus/dedup.tsv\" |
  .nextflow.bin = \"${tmp}/opt/nextflow\" |
  .nextflow.home = \"${tmp}/opt/nxf-home\"
" "${ROOT}/config/pin.yaml" >"${tmp}/config/pin.yaml"

printf 'ACGT\n' >"${tmp}/ref/hg38.fa"
echo "$fasta_md5" >"${tmp}/ref/hg38.fa.stamp"
cat >"${tmp}/ref/hg38.gtf" <<'GTF'
chr1	source	gene	1	100	.	+	.	.
chr1	source	CDS	10	20	.	+	0	.
GTF
echo "$gtf_md5" >"${tmp}/ref/hg38.gtf.stamp"
printf '>v1\nACGT\n' >"${tmp}/ref/virus/ctat.fasta"
printf '>v1\nACGT\n' >"${tmp}/ref/virus/viral.fasta"
: >"${tmp}/ref/virus/dedup.tsv"
mkdir -p "${tmp}/ref/kraken2/hg38"
touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

mkdir -p "${tmp}/opt"
cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
echo "nextflow version 24.10.5" >&2
exit 0
EOF
chmod +x "${tmp}/opt/nextflow"

mock_bin="${tmp}/bin"
mkdir -p "$mock_bin"
for f in "${ROOT}/bin"/*.sh; do
  base="$(basename "$f")"
  [[ "$base" == check.sh ]] && continue
  ln -sf "$f" "${mock_bin}/${base}"
done
cat >"${mock_bin}/check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${mock_bin}/check.sh" "${mock_bin}/run_cohort.sh"

mk_site() {
  local sarek_en="$1" vi_en="$2" vm_en="$3" out="$4"
  cat >"$out" <<YAML
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
    enabled: ${vi_en}
  sarek:
    enabled: ${sarek_en}
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: ${vm_en}
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${ROOT}/config/nextflow/local.config
YAML
}

run_dry() {
  local cfg="$1"
  ALLCALL_PIN="${tmp}/config/pin.yaml" "${mock_bin}/run_cohort.sh" \
    --config "$cfg" --run-name drytest --dry-run 2>/dev/null
}

vi_only="${tmp}/vi-only.yaml"
mk_site false true false "$vi_only"
mapfile -t lines < <(run_dry "$vi_only")

nf_lines=()
for line in "${lines[@]}"; do
  [[ "$line" == *" run nf-core/"* ]] || continue
  [[ "$line" == *" -params-file "* ]] && {
    echo "test_run_cohort_dry_run: launcher must not use -params-file (regression NF24 VI)" >&2
    exit 1
  }
  [[ "$line" == *" -c "* ]] || {
    echo "test_run_cohort_dry_run: expected -c config flag in: $line" >&2
    exit 1
  }
  nf_lines+=("$line")
done

[[ "${#nf_lines[@]}" -eq 2 ]] || {
  echo "test_run_cohort_dry_run: VI-only expected 2 nf lines (VI + SNP stub), got ${#nf_lines[@]}" >&2
  exit 1
}
[[ "${nf_lines[0]}" == *"nf-core/viralintegration"* ]] || {
  echo "test_run_cohort_dry_run: first line should be viralintegration" >&2
  exit 1
}
[[ "${nf_lines[1]}" == *"nf-core/sarek"* ]] || {
  echo "test_run_cohort_dry_run: second line should be sarek SNP params" >&2
  exit 1
}
[[ "${nf_lines[0]}" == *"${ROOT}/config/nextflow/local.config"* ]] || {
  echo "test_run_cohort_dry_run: missing nextflow_configs overlay -c" >&2
  exit 1
}

vi_params="${tmp}/results/drytest/params/viralintegration.config"
[[ -f "$vi_params" ]] || {
  echo "test_run_cohort_dry_run: missing ${vi_params}" >&2
  exit 1
}
grep -q 'viral_fasta' "$vi_params" || {
  echo "test_run_cohort_dry_run: viralintegration params need viral_fasta (not virus_fasta)" >&2
  exit 1
}
grep -q 'virus_fasta' "$vi_params" && {
  echo "test_run_cohort_dry_run: obsolete virus_fasta key still present" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$vi_params" || {
  echo "test_run_cohort_dry_run: missing max_cpus cap" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$vi_params" || {
  echo "test_run_cohort_dry_run: missing max_memory cap" >&2
  exit 1
}

all_on="${tmp}/all-on.yaml"
mk_site true true true "$all_on"
mapfile -t all_lines < <(run_dry "$all_on")
count=0
for line in "${all_lines[@]}"; do
  [[ "$line" == *" run nf-core/"* ]] && count=$((count + 1))
done
[[ "$count" -eq 4 ]] || {
  echo "test_run_cohort_dry_run: all pipelines on expected 4 nf lines, got ${count}" >&2
  exit 1
}

matrix="${tmp}/results/drytest/matrix.tsv"
[[ -f "$matrix" ]] || {
  echo "test_run_cohort_dry_run: dry-run should write matrix.tsv" >&2
  exit 1
}
awk -F'\t' 'NR==2 && $2=="running" { ok=1 } END { exit ok ? 0 : 1 }' "$matrix" || {
  echo "test_run_cohort_dry_run: matrix should mark viralintegration running for S1" >&2
  exit 1
}

echo "test_run_cohort_dry_run: ok"
